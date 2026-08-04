import os  
fn = r'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/final_report.py'  
data = open(fn, 'r', encoding='utf-8').read()  
old = \"ax.set_title(f'{label}: Net={b['residual']:.2f} MW')\"  
new = \"ax.set_title('{}: Net={:.2f} MW'.format(label, b['residual']))\"  
data = data.replace(old, new)  
open(fn, 'w', encoding='utf-8').write(data)  
print('Fixed line. Count:', data.count('residual')) 
