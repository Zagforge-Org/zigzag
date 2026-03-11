const STORAGE_KEY = "zz-theme";
const root = document.documentElement;

export type Theme = "dark" | "light";

function getSystemTheme(): Theme {
    return window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light";
}

/** Call once on page load (before rendering) to apply stored or system theme. */
export function initTheme(): void {
    const stored = localStorage.getItem(STORAGE_KEY) as Theme | null;
    root.setAttribute("data-theme", stored ?? getSystemTheme());
}

/** Toggle between dark and light; persists choice to localStorage. */
export function toggleTheme(): void {
    const current =
        root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", current);
    localStorage.setItem(STORAGE_KEY, current);
}
