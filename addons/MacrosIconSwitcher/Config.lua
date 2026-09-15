-- Config.lua | MacrosIconSwitcher | Retail 12.1.0
-- UI constants and defaults. Data lives in the saved variable MacrosIconSwitcherDB.

MacrosIconSwitcherConfig = MacrosIconSwitcherConfig or {}

MacrosIconSwitcherConfig.UI = {
    WIDTH = 600,
    HEIGHT = 460,
    ROW_HEIGHT = 28,
    HEADER_HEIGHT = 22,
    COL_CHECK = 26,
    COL_NAME = 230,
    COL_CURRENT = 130,
    COL_ICON = 150,
    LEFT = 8,
    SCROLLBAR = 24,
}

MacrosIconSwitcherConfig.COLORS = {
    HEADER = { 1.00, 0.82, 0.00 },
    MUTED  = { 0.70, 0.70, 0.70 },
    OK     = { 0.20, 0.90, 0.30 },
    ERR    = { 1.00, 0.35, 0.35 },
    ROW_A  = { 1.00, 1.00, 1.00, 0.03 },
    ROW_B  = { 0.00, 0.00, 0.00, 0.00 },
}
