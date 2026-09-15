-- Config.lua | MacrosIconSwitcher | Retail 12.1.0
-- UI constants and defaults. Data lives in the saved variable MacrosIconSwitcherDB.

MacrosIconSwitcherConfig = MacrosIconSwitcherConfig or {}

MacrosIconSwitcherConfig.UI = {
    WIDTH = 650,
    HEIGHT = 460,
    ROW_HEIGHT = 28,
    HEADER_HEIGHT = 22,
    COL_CHECK = 26,
    COL_NAME = 230,
    COL_CURRENT = 120,
    COL_PREVIEW = 46,
    COL_ICON = 176,
    LEFT = 8,
    SCROLLBAR = 24,
}

MacrosIconSwitcherConfig.PICKER = {
    WIDTH = 296,
    HEIGHT = 380,
    CELL = 34,
    COLS = 8,
    PAD = 12,
}

MacrosIconSwitcherConfig.MINIMAP = {
    PADDING = 4, -- gap between minimap edge and button (radius is dynamic: map width / 2 + PADDING)
    ICON = 134400, -- same FileDataID as ## IconTexture in the .toc
}

MacrosIconSwitcherConfig.COLORS = {
    HEADER = { 1.00, 0.82, 0.00 },
    MUTED  = { 0.70, 0.70, 0.70 },
    OK     = { 0.20, 0.90, 0.30 },
    ERR    = { 1.00, 0.35, 0.35 },
    ROW_A  = { 1.00, 1.00, 1.00, 0.03 },
    ROW_B  = { 0.00, 0.00, 0.00, 0.00 },
}
