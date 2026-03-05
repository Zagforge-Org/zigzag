import { M } from "./state";
import { initContentWorker } from "./content";
import { renderHeader, renderCards } from "./header";
import { renderLangChart, renderSizeChart } from "./charts";
import { buildTableDOM, renderTable } from "./table";
import { startWatchMode } from "./watch";

initContentWorker(document.getElementById("fc")!.textContent!);

renderHeader();
renderCards();
renderLangChart();
renderSizeChart();

const tableViewport = buildTableDOM();
document.getElementById("files-table")!.appendChild(tableViewport);
renderTable();

if (M.watch_mode) {
    startWatchMode();
}
