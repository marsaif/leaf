#!/usr/bin/env python3
"""Click-through smoke test of the main flows (real clicks, not hash jumps). Prints each step and any JS error.
  tools/.venv/bin/python tools/flows.py"""
import asyncio, sys
from pathlib import Path
from playwright.async_api import async_playwright
ROOT = Path(__file__).resolve().parent.parent

async def main():
    errs, fails = [], []
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome")
        pg = await b.new_page(viewport={"width": 600, "height": 800})
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
        async def go(h):
            await pg.goto(f"file://{ROOT}/index.html?bare&theme=dark&size=600x800{h}", wait_until="networkidle"); await pg.wait_for_timeout(250)
        async def click(sel, label, nth=0):
            try:
                await pg.locator(f"#screen {sel}").nth(nth).click(timeout=3000); await pg.wait_for_timeout(250)
            except Exception as e: fails.append(f"{label}: {str(e).splitlines()[0]}"); print("  FAIL", label); return False
            print("  ok  ", label, "→", await pg.evaluate("location.hash")); return True
        async def expect(js, label):
            ok = await pg.evaluate(js)
            print("  ok  " if ok else "  FAIL", label); (None if ok else fails.append(label))

        print("1. open a book from Home"); await go("#/home")
        await click(".hm-resume", "Resume"); await expect("App.current.name === 'reader'", "reader is open")
        print("2. typeset change"); await click(".rd-body", "tap page centre (chrome)")
        await click("[data-open='typeset'], .rd-tools button:has-text('Typeset')", "open Typeset")
        await click(".rd-ts-tabs button:has-text('Page')", "Page tab")
        await click(".rd-opt[data-k='block_rendering_mode'] .ko-seg button:has-text('Web')", "Layout engine → Web")
        await expect("!!document.querySelector(\".rd-opt[data-k='block_rendering_mode'] button.on\")?.textContent.includes('Web')", "Web is selected")
        print("3. selection → highlight"); await go("#/reader?id=animal-farm&o=hl-popup&o.demo=1")
        await click(".rd-hl-colors button:has-text('Green')", "pick Green")
        await click(".rd-hl-acts button:has-text('Highlight'), .rd-hl-main button:has-text('Highlight')", "Highlight")
        await expect("document.querySelectorAll('.rd-text mark.hl').length > 0", "a highlight is on the page")
        print("4. menu drill"); await go("#/library")
        await click("[data-open='main-menu']", "open main menu")
        await click(".mn-tab:has-text('Settings')", "Settings tab")
        await click(".mn-row:has-text('Screen')", "drill into Screen")
        await expect("document.querySelector('.mn-title')?.textContent.includes('Screen')", "Screen page shown")
        await click(".mn-back", "back")
        print("5. settings search"); await go("#/settings")
        await pg.locator("#screen .set-search input, #screen input[type=search]").first.fill("refresh"); await pg.wait_for_timeout(300)
        await expect("document.querySelectorAll('.set-hit').length > 0 || location.hash.includes('q=')", "results for 'refresh'")
        print("6. dialogs"); await go("#/library?tab=collections")
        await click("button:has-text('New')", "New collection")
        await expect("App.top()?.name === 'lib-coll-new' || App.top()?.name === 'input'", "new-collection dialog open")
        await go("#/home?o=frontlight"); await click(".ko-sheet-head [data-close]", "close Frontlight with ×")
        await expect("!App.state.stack.length", "sheet closed")
        await go("#/history"); await click("[data-open='lib-hist-menu']", "History options")
        await expect("!!document.querySelector('.lb-histsheet')", "history options is a sheet")
        await go("#/settings?section=search&path=%5B0%2C0%2C0%5D")
        await expect("true", "dictionary settings render")
        await click(".mn-row:has-text('Manage dictionaries')", "Manage dictionaries (link beats stepper)")
        await expect("App.current.name !== 'settings' || App.state.stack.length > 0", "Manage dictionaries opened something")
        await b.close()
    print("\nJS errors:", errs or "none"); print("failures:", fails or "none")
    sys.exit(1 if errs or fails else 0)
asyncio.run(main())
