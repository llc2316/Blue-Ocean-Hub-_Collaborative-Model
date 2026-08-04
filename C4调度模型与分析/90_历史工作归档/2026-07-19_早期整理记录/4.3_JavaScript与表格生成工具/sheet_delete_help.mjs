import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
const path = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.xlsx";
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheet = wb.worksheets.getItem("08_4.8-4.9目标架构");
console.log(Object.getOwnPropertyNames(Object.getPrototypeOf(sheet)).sort().join("\n"));
console.log("COLLECTION");
console.log(Object.getOwnPropertyNames(Object.getPrototypeOf(wb.worksheets)).sort().join("\n"));
