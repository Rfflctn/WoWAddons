-- UI.lua | DecorLumberProfit | Retail 12.1.0
-- Неймспейс UI + общее состояние (Этап 8). Владелец состояния — этот файл;
-- остальные UI/* только читают/пишут через UI._x (кросс-файловых locals нет).
-- Рендер — UI/TableView.lua, окно — UI/MainFrame.lua, действия — UI/Actions.lua,
-- статус — UI/Status.lua, тултипы — UI/Tooltip.lua, команды/события — UI/Commands.lua,
-- попапы — UI/Popups.lua. Все тексты — через L/TL из Locales.lua (ru/en).

DecorLumberProfitUI = {}
local UI = DecorLumberProfitUI

UI.FRAME_NAME = "DecorLumberProfitFrame"

-- Общее состояние
UI._mainFrame = nil
UI._scrollChild = nil
UI._scrollFrame = nil
UI._statusText = nil
UI._healthDot = nil
UI._headerFrame = nil
UI._lastLayoutW = nil
UI._currentRecipes = {}
UI._displayList = {} -- [{rec=,eco=}] — отрисованный вид (после фильтра/сортировки)
UI.displayList = UI._displayList -- legacy alias для /dump
UI._rows = {}
UI._sortKey = nil
UI._sortDesc = false
UI._topMode = false
UI._lastRowCount = nil
UI.hideUnlearned = false
UI._loadedFromDB = false
UI._hiddenColumns = {} -- { [colKey] = true } — скрытые колонки (панель «Столбцы», персист в DB.settings)
UI._columnsPanel = nil
UI._colChecks = {}
UI._rowHeightLabel = nil -- цифра степпера высоты строк в футере (MainFrame)
UI._minimized = false -- окно свёрнуто (только заголовок; кнопка «–» в MainFrame)
UI._savedHeight = nil -- высота до сворачивания (восстанавливаем при разворачивании)
UI._minimizeBtn = nil -- кнопка свернуть/развернуть (MainFrame)
UI._contentWidgets = nil -- виджеты контента, прячущиеся при сворачивании (MainFrame)
UI._resizeGrip = nil -- уголок ресайза (MainFrame, прячется при сворачивании)
UI._headerLine = nil -- линия под шапкой (MainFrame, прячется при сворачивании)
UI._hideLabelFallback = nil -- подпись chkHide при отсутствии chk.Text (MainFrame)

_G.DecorLumberProfitUI = UI
