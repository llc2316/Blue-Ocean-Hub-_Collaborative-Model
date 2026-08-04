import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const workbookPath = path.resolve(
  "../../V4整合/modules/4.5_storage_hydrogen/reference_model/电能制氢模型多表合一.xlsx",
);
const outputDir = path.resolve("rendered");
await fs.mkdir(outputDir, { recursive: true });
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(workbookPath));
const sheets = await workbook.inspect({ kind: "sheet", include: "id,name", maxChars: 4000 });
console.log("SHEETS");
console.log(sheets.ndjson);
const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 12000,
  tableMaxRows: 12,
  tableMaxCols: 12,
  tableMaxCellChars: 120,
});
console.log("OVERVIEW");
console.log(overview.ndjson);
const formulas = await workbook.inspect({
  kind: "formula",
  maxChars: 20000,
  options: { maxResults: 400 },
});
console.log("FORMULAS");
console.log(formulas.ndjson);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
console.log("ERRORS");
console.log(errors.ndjson);
for (const name of ["1_先看这里", "2_输入参数", "3_最优分配", "4_收益与成本", "5_敏感性分析"]) {
  const image = await workbook.render({ sheetName: name, autoCrop: "all", scale: 1.5, format: "png" });
  await fs.writeFile(path.join(outputDir, `${name}.png`), new Uint8Array(await image.arrayBuffer()));
}
