import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const path = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.xlsx";
const tempPath = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.tmp.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const target = wb.worksheets.getItem("08_4.8-4.9目标架构");
target.delete();
const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(tempPath);
await fs.rename(tempPath, path);
console.log((await wb.inspect({ kind: "sheet", include: "id,name", maxChars: 5000 })).ndjson);
console.log((await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, maxChars: 3000 })).ndjson);
