/*
Convert a plain-text `pg_dump` SQL file that uses `COPY ... FROM stdin` blocks into
an INSERT-based SQL file that can be executed by GUI query tools (pgAdmin/DBeaver/etc).

Usage:
  node backend/scripts/convert_pg_dump_to_inserts.js <input.sql> <output.sql>

Notes:
- This is slower to restore than COPY, but works in tools that only run plain SQL.
- The input must be a *plain* format pg_dump (not custom/tar).
*/

const fs = require('fs');
const path = require('path');
const readline = require('readline');

function unescapeCopyText(field) {
  // COPY text format backslash escapes.
  // https://www.postgresql.org/docs/current/sql-copy.html
  let out = '';
  for (let i = 0; i < field.length; i++) {
    const ch = field[i];
    if (ch !== '\\') {
      out += ch;
      continue;
    }

    // Trailing backslash: keep as-is.
    if (i + 1 >= field.length) {
      out += '\\';
      break;
    }

    const next = field[++i];
    switch (next) {
      case 'b':
        out += '\b';
        break;
      case 'f':
        out += '\f';
        break;
      case 'n':
        out += '\n';
        break;
      case 'r':
        out += '\r';
        break;
      case 't':
        out += '\t';
        break;
      case 'v':
        out += '\v';
        break;
      case '\\':
        out += '\\';
        break;
      case 'x': {
        // \xHH
        const h1 = field[i + 1];
        const h2 = field[i + 2];
        if (h1 && h2 && /[0-9a-fA-F]/.test(h1) && /[0-9a-fA-F]/.test(h2)) {
          out += String.fromCharCode(parseInt(h1 + h2, 16));
          i += 2;
        } else {
          // Not actually hex; treat literally.
          out += 'x';
        }
        break;
      }
      default: {
        // Octal escapes: \ooo (up to 3 digits).
        if (/[0-7]/.test(next)) {
          let oct = next;
          for (let k = 0; k < 2; k++) {
            const peek = field[i + 1];
            if (peek && /[0-7]/.test(peek)) {
              oct += peek;
              i++;
            } else {
              break;
            }
          }
          out += String.fromCharCode(parseInt(oct, 8));
        } else {
          // Any other escaped char represents itself.
          out += next;
        }
      }
    }
  }
  return out;
}

function escapeForPostgresEString(value) {
  // Produces a content string safe to embed in E'...'
  // Backslashes must be doubled, quotes doubled.
  // Control chars are represented with backslash escapes.
  let out = '';
  for (let i = 0; i < value.length; i++) {
    const ch = value[i];
    switch (ch) {
      case '\\':
        out += '\\\\';
        break;
      case "'":
        out += "''";
        break;
      case '\n':
        out += '\\n';
        break;
      case '\r':
        out += '\\r';
        break;
      case '\t':
        out += '\\t';
        break;
      case '\b':
        out += '\\b';
        break;
      case '\f':
        out += '\\f';
        break;
      case '\v':
        out += '\\v';
        break;
      default:
        out += ch;
    }
  }
  return out;
}

async function writeLine(writer, line) {
  if (!writer.write(line + '\n')) {
    await new Promise((resolve) => writer.once('drain', resolve));
  }
}

function usageAndExit(code) {
  const exe = path.basename(process.argv[1] || 'convert_pg_dump_to_inserts.js');
  console.error(`Usage: node ${exe} <input.sql> <output.sql>`);
  process.exit(code);
}

async function main() {
  const inputPath = process.argv[2];
  const outputPath = process.argv[3];
  if (!inputPath || !outputPath) usageAndExit(2);

  const input = fs.createReadStream(inputPath, { encoding: 'utf8' });
  const rl = readline.createInterface({ input, crlfDelay: Infinity });
  const writer = fs.createWriteStream(outputPath, { encoding: 'utf8' });

  let inCopy = false;
  let copyTable = null;
  let copyColumns = null;

  // Example:
  // COPY public.table_name (col1, col2, col3) FROM stdin;
  const copyHeaderRe = /^COPY\s+([^\s]+)\s*\((.*)\)\s+FROM\s+stdin;\s*$/;

  try {
    for await (const rawLine of rl) {
      const line = rawLine;

      if (!inCopy) {
        const m = line.match(copyHeaderRe);
        if (m) {
          inCopy = true;
          copyTable = m[1];
          copyColumns = m[2]
            .split(',')
            .map((c) => c.trim())
            .filter(Boolean);

          await writeLine(
            writer,
            `-- Converted from: ${line}`
          );
          continue;
        }

        // Drop `\.` terminators if any appear outside COPY blocks (defensive).
        if (line === '\\.') continue;

        await writeLine(writer, line);
        continue;
      }

      // In COPY block
      if (line === '\\.') {
        inCopy = false;
        copyTable = null;
        copyColumns = null;
        await writeLine(writer, '');
        continue;
      }

      const fields = line.split('\t');
      const values = fields.map((field) => {
        if (field === '\\N') return 'NULL';
        const unescaped = unescapeCopyText(field);
        return `E'${escapeForPostgresEString(unescaped)}'`;
      });

      // If column counts don't match, still emit an INSERT (it will fail at restore time)
      // but this makes the mismatch obvious in error output.
      const colsSql = copyColumns && copyColumns.length
        ? `(${copyColumns.join(', ')})`
        : '';

      await writeLine(
        writer,
        `INSERT INTO ${copyTable} ${colsSql} VALUES (${values.join(', ')});`
      );
    }

    if (inCopy) {
      throw new Error('Unexpected EOF while inside a COPY ... FROM stdin block (missing \\.).');
    }
  } finally {
    writer.end();
  }
}

main().catch((err) => {
  console.error('Conversion failed:', err && err.stack ? err.stack : err);
  process.exit(1);
});
