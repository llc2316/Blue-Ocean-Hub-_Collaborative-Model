import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
const path = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_enterprise_exchange_pack/4.3企业交流会前工作包.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
for (const [sheet, range] of [["01_深圳能源定向清单","A4:J23"],["02_明阳风电定向清单","A4:J25"],["03_公开已知_无需再问","A4:H16"],["04_4.3模型接口图","A1:P34"]]) {
  console.log((await wb.inspect({kind:"region",sheetId:sheet,range,maxChars:5000,tableMaxRows:6,tableMaxCols:10,tableMaxCellChars:120})).ndjson);
}
console.log((await wb.inspect({kind:"match",searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",options:{useRegex:true,maxResults:100},maxChars:3000})).ndjson);
