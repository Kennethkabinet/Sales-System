$f = 'C:\Users\Kenneth\Desktop\sales-system\frontend\sales_frontend\lib\screens\dashboard_screen.dart'
$lines = Get-Content $f -Encoding UTF8
$a = 0; $b = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'class _ActiveUsersList') { $a = $i }
  if ($lines[$i] -match 'class _ActionChip') { $b = $i }
}
Write-Host "ActiveUsersList at index $a (line $($a+1)), ActionChip at index $b (line $($b+1))"
# Remove from empty line before _ActiveUsersList to just before _ActionChip
# i.e., remove indices ($a-1) through ($b-1)
$newLines = $lines[0..($a-2)] + $lines[$b..($lines.Count-1)]
[System.IO.File]::WriteAllLines($f, $newLines, [System.Text.Encoding]::UTF8)
Write-Host "Done. New count: $($newLines.Count)"
