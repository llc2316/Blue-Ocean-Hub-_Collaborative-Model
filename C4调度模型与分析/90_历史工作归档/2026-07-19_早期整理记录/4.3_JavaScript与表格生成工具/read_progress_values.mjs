import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
const path = "C:/Users/llcqc/Desktop/多源能源/进度安排.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheet = wb.worksheets.getItemAt(0);
const values = sheet.getRange("A1:W16").values;
for (let i = 0; i < values.length; i++) {
  const cells = values[i].map((v,j)=>v===null||v===""?null:`${String.fromCharCode(65+j)}=${String(v).replace(/\s+/g," ")}`).filter(Boolean);
  if (cells.length) console.log(`${i+1}: ${cells.join(" | ")}`);
}
