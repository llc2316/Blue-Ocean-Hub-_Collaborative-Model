import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "../../V4整合/modules/4.5_storage_hydrogen/reference_model/电能制氢模型多表合一.xlsx";
const blob = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(blob);

const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 12000,
  tableMaxRows: 12,
  tableMaxCols: 10,
  tableMaxCellChars: 100,
});
console.log("OVERVIEW");
console.log(overview.ndjson);

const formulas = await workbook.inspect({
  kind: "formula",
  maxChars: 12000,
  options: { maxResults: 200 },
});
console.log("FORMULAS");
console.log(formulas.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 200 },
  maxChars: 6000,
});
console.log("ERRORS");
console.log(errors.ndjson);

const renderNames = workbook.worksheets.items.map((sheet) => sheet.name);
let renderIndex = 0;
for (const name of renderNames) {
  try {
    const rendered = await workbook.render({ sheetName: name, autoCrop: "all", scale: 1, format: "png" });
    const bytes = new Uint8Array(await rendered.arrayBuffer());
    await import("node:fs/promises").then(fs => fs.writeFile(`render_${renderIndex}.png`, bytes));
    console.log(`RENDERED ${name}`);
  } catch (error) {
    console.log(`RENDER_FAILED ${name}: ${error?.message ?? error}`);
  }
  renderIndex += 1;
}
