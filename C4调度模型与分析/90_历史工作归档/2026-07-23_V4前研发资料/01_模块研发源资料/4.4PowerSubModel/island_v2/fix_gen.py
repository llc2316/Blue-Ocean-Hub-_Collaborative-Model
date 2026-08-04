import os  
import re  
src = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_v2\gen.py'  
with open(src, 'rb') as f:  
    content = f.read()  
marker = b'# ======== Report'  
idx = content.find(marker)  
if idx >= 0: content = content[:idx]  
dst = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_v2\gen_clean.py'  
with open(dst, 'wb') as f: f.write(content)  
print(len(content.splitlines()), 'lines written') 
