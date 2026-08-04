import os  
fn = 'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/final_report.py'  
data = open(fn, 'r', encoding='utf-8').read()  
idx = data.find('# ======== Report Generator')  
if idx >= 0: data = data[:idx]  
old = 'ax.set_ylabel' + chr(39) + 'Power [MW]' + chr(39) + '; ax.set_title(f' + chr(39) + '{label}: Net={b[' + chr(39) + 'residual' + chr(39) + ']:.2f} MW' + chr(39) + ')'  
new = 'ax.set_ylabel' + chr(39) + 'Power [MW]' + chr(39) + '; ax.set_title(' + chr(39) + '{}: Net={:.2f} MW' + chr(39) + '.format(label, b[' + chr(39) + 'residual' + chr(39) + ']))'  
data = data.replace(old, new)  
open(fn, 'w', encoding='utf-8').write(data)  
print('Fixed. Lines:', len(data.splitlines())) 
