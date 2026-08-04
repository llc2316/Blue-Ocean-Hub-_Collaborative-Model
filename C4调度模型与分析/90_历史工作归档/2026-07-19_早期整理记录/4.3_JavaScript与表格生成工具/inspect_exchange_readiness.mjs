import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const matrixPath = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.xlsx";
const progressPath = "C:/Users/llcqc/Desktop/多源能源/进度安排.xlsx";

const matrix = await SpreadsheetFile.importXlsx(await FileBlob.load(matrixPath));
for (const spec of [
  ["06_企业交流清单", "A1:J32", 30000],
  ["03_国产参考设备", "A1:K20", 16000],
  ["05_证据矩阵", "A1:N35", 26000],
  ["09_多目标企业交流清单", "A1:L33", 30000],
]) {
  const result = await matrix.inspect({ kind: "region", sheetId: spec[0], range: spec[1], maxChars: spec[2], tableMaxRows: 40, tableMaxCols: 14, tableMaxCellChars: 180 });
  console.log(`---MATRIX:${spec[0]}---`);
  console.log(result.ndjson);
}

const progress = await SpreadsheetFile.importXlsx(await FileBlob.load(progressPath));
console.log("---PROGRESS:SHEETS---");
console.log((await progress.inspect({ kind: "sheet", include: "id,name", maxChars: 6000 })).ndjson);
for (const sheet of progress.worksheets.items) {
  const used = sheet.getUsedRange();
  if (!used) continue;
  console.log(`---PROGRESS:${sheet.name}:${used.address}---`);
  console.log((await progress.inspect({ kind: "region", sheetId: sheet.name, range: used.address, maxChars: 30000, tableMaxRows: 60, tableMaxCols: 20, tableMaxCellChars: 200 })).ndjson);
}
