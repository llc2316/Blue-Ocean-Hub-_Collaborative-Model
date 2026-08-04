import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "C:/Users/llcqc/Desktop/多源能源/4_3_data_freeze/蓝海枢纽_4.3数据冻结与证据矩阵.xlsx";
const outDir = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update/previews_before";
await fs.mkdir(outDir, { recursive: true });
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const info = await wb.inspect({ kind: "sheet", include: "id,name", maxChars: 5000 });
console.log(info.ndjson);
const region = await wb.inspect({ kind: "region", sheetId: "06_企业交流清单", range: "A1:L30", maxChars: 14000 });
console.log(region.ndjson);
const png = await wb.render({ sheetName: "06_企业交流清单", autoCrop: "all", scale: 1, format: "png" });
await fs.writeFile(`${outDir}/06_企业交流清单_before.png`, new Uint8Array(await png.arrayBuffer()));
