import { _ReportMeta } from "./state";
import { renderHeader, renderCards } from "./header";
import { renderLangChart, renderSizeChart } from "./charts";
import { buildTableDOM, renderTable, getTotalCount } from "./table";
import { startWatchMode } from "./watch";
import { initTheme, toggleTheme } from "./theme";

// Apply theme before any rendering
initTheme();

// Wire theme toggle
const themeBtn = document.getElementById("theme-toggle");
if (themeBtn) themeBtn.addEventListener("click", toggleTheme);

renderHeader();
renderCards();
renderLangChart();
renderSizeChart();

const tableViewport = buildTableDOM();
document.getElementById("files-table")!.appendChild(tableViewport);

// Wire search clear + count badge
const searchEl = document.getElementById("search") as HTMLInputElement | null;
const clearBtn = document.getElementById(
    "search-clear",
) as HTMLButtonElement | null;
const countEl = document.getElementById("search-count") as HTMLElement | null;

function refreshSearchUI(): void {
    const q = searchEl?.value.trim() ?? "";
    const matched = renderTable();
    const total = getTotalCount();
    if (clearBtn) clearBtn.classList.toggle("visible", q.length > 0);
    if (countEl)
        countEl.textContent = q
            ? `${matched} / ${total} files`
            : `${total} files`;
}

if (searchEl) {
    searchEl.addEventListener("input", refreshSearchUI);
}
if (clearBtn) {
    clearBtn.addEventListener("click", () => {
        if (searchEl) searchEl.value = "";
        refreshSearchUI();
    });
}

// Initial render + count
refreshSearchUI();

if (_ReportMeta.watch_mode) {
    startWatchMode();
}
