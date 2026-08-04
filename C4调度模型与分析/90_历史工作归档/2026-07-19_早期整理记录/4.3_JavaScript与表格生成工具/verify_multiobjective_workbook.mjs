import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const path = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
console.log((await wb.inspect({ kind: "sheet", include: "id,name", maxChars: 5000 })).ndjson);
console.log((await wb.inspect({ kind: "region", sheetId: "06_企业交流清单", range: "A20:J32", maxChars: 10000 })).ndjson);
console.log((await wb.inspect({ kind: "region", sheetId: "08_4.8-4.9目标架构", range: "A15:L19", maxChars: 12000 })).ndjson);
console.log((await wb.inspect({ kind: "region", sheetId: "09_多目标企业交流清单", range: "A4:L33", maxChars: 12000 })).ndjson);
console.log((await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, maxChars: 4000 })).ndjson);
