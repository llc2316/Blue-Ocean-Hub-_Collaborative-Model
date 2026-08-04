import os  
fn = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_power_balance\model.py'  
with open(fn, 'r', encoding='utf-8', errors='replace') as f:  
    content = f.read()  
old_line = 'self.p_residual = s + g + b_net + e + d + x + m + sp + lp)'  
new_line = 'self.p_residual = s + g + b_net - e - d - x - m - sp - lp'  
content = content.replace(old_line, new_line)  
with open(fn, 'w', encoding='utf-8') as f:  
    f.write(content)  
print('Fixed:', old_line in content, '- was present') 
