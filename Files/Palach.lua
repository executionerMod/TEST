script_name("ExecutionerLoader")
script_version("1.0")
script_author("ExecutionerMod")

require "lib.moonloader"

local imgui = require "mimgui"
local ffi = require 'ffi'

local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

MONET_DPI_SCALE = MONET_DPI_SCALE or 1.0
local S = MONET_DPI_SCALE

local cU32 = imgui.ColorConvertFloat4ToU32

-- ============================================================
-- КОНФИГ
-- ============================================================
local VALID_KEY  = "123"
local SCRIPT_URL = "https://pastebin.com/raw/vCRxS1VF"

-- Путь для загрузки — та же папка monetloader
local MONET_DIR   = "/storage/emulated/0/Android/media/com.arizona.game/monetloader/"
local SCRIPT_NAME = ".exec_" .. tostring(os.time()) .. ".lua"
local SCRIPT_PATH = MONET_DIR .. SCRIPT_NAME

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================
local loaderOpen  = imgui.new.bool(true)
local keyBuffer   = imgui.new.char[64]()
local statusText  = ""
local statusColor = imgui.ImVec4(0.65, 0.68, 0.75, 1)
local isChecking  = false
local isLoaded    = false

-- ============================================================
-- ФИКС ШРИФТА
-- ============================================================
imgui.OnInitialize(function()
    imgui.SwitchContext()
    local io_ = imgui.GetIO()
    local glyph_ranges = io_.Fonts:GetGlyphRangesCyrillic()

    local paths = {
        "/system/fonts/Roboto-Regular.ttf",
        "/system/fonts/DroidSans.ttf",
        "C:\\Windows\\Fonts\\segoeui.ttf",
        "C:\\Windows\\Fonts\\arial.ttf",
    }

    for _, p in ipairs(paths) do
        local f = io_.Fonts:AddFontFromFileTTF(p, 15 * S, nil, glyph_ranges)
        if f then break end
    end

    local s = imgui.GetStyle()
    s.WindowRounding   = 12
    s.FrameRounding    = 7
    s.WindowBorderSize = 1.5
    s.WindowPadding    = imgui.ImVec2(0, 0)
end)

-- ============================================================
-- ЦВЕТА
-- ============================================================
local C = {
    bg_window   = imgui.ImVec4(0.07, 0.08, 0.11, 0.98),
    bg_input    = imgui.ImVec4(0.13, 0.15, 0.20, 1.0),
    bg_button   = imgui.ImVec4(0.22, 0.48, 0.85, 1.0),
    bg_button_h = imgui.ImVec4(0.30, 0.55, 0.92, 1.0),
    text_white  = imgui.ImVec4(0.96, 0.97, 0.99, 1.0),
    text_gray   = imgui.ImVec4(0.62, 0.66, 0.74, 1.0),
    text_dim    = imgui.ImVec4(0.45, 0.48, 0.55, 0.85),
    accent      = imgui.ImVec4(0.35, 0.60, 1.00, 1.0),
    success     = imgui.ImVec4(0.40, 0.90, 0.50, 1.0),
    error_red   = imgui.ImVec4(0.92, 0.35, 0.35, 1.0),
    warning     = imgui.ImVec4(1.00, 0.75, 0.30, 1.0),
    border      = imgui.ImVec4(0.30, 0.55, 0.95, 0.30),
}

-- ============================================================
-- УТИЛИТЫ
-- ============================================================
local function setStatus(text, color)
    statusText  = text
    statusColor = color or C.text_gray
end

local function secureDelete(path)
    local f = io.open(path, "wb")
    if f then
        local garbage = ""
        for i = 1, 1024 do
            garbage = garbage .. string.char(math.random(0, 255))
        end
        f:write(garbage)
        f:flush()
        f:close()
    end
    os.remove(path)
end

-- ============================================================
-- СКАЧИВАНИЕ ФАЙЛА (метод из твоего примера — JNI Java HTTP)
-- ============================================================
local function downloadFile(url, path, callback)
    lua_thread.create(function()
        setStatus(u8"Подключение...", C.warning)

        local ok = false

        -- === МЕТОД 1: JNI Java HTTP ===
        local function tryJavaDownload()
            local jniOk, jni = pcall(require, "android.jnienv-util")
            if not jniOk then return false end

            local envOk, env = pcall(require, "android.jnienv")
            if not envOk then return false end

            local success = pcall(function()
                local jvm = env.getJVM()
                if not jvm then return end

                local jnienv = jvm:AttachCurrentThread()
                if not jnienv then return end

                local URLClass = jnienv:FindClass("java/net/URL")
                local URLInit = jnienv:GetMethodID(URLClass, "<init>", "(Ljava/lang/String;)V")
                local openConn = jnienv:GetMethodID(URLClass, "openConnection", "()Ljava/net/URLConnection;")

                local jUrl = jnienv:NewObject(URLClass, URLInit, jnienv:NewStringUTF(url))
                local conn = jnienv:CallObjectMethod(jUrl, openConn)

                local HttpClass = jnienv:FindClass("java/net/HttpURLConnection")
                local setConnTimeout = jnienv:GetMethodID(HttpClass, "setConnectTimeout", "(I)V")
                local setReadTimeout = jnienv:GetMethodID(HttpClass, "setReadTimeout", "(I)V")
                local connect = jnienv:GetMethodID(HttpClass, "connect", "()V")
                local getInputStream = jnienv:GetMethodID(HttpClass, "getInputStream", "()Ljava/io/InputStream;")

                jnienv:CallVoidMethod(conn, setConnTimeout, 10000)
                jnienv:CallVoidMethod(conn, setReadTimeout, 15000)
                jnienv:CallVoidMethod(conn, connect)

                local stream = jnienv:CallObjectMethod(conn, getInputStream)

                local StreamClass = jnienv:FindClass("java/io/InputStream")
                local readMethod = jnienv:GetMethodID(StreamClass, "read", "([B)I")
                local byteArray = jnienv:NewByteArray(8192)

                local file = io.open(path, "wb")
                if not file then return end

                local totalBytes = 0
                while true do
                    local bytesRead = jnienv:CallIntMethod(stream, readMethod, byteArray)
                    if bytesRead <= 0 then break end

                    local bytes = jnienv:GetByteArrayElements(byteArray, nil)
                    local chunk = ffi.string(bytes, bytesRead)
                    file:write(chunk)
                    jnienv:ReleaseByteArrayElements(byteArray, bytes, 0)
                    totalBytes = totalBytes + bytesRead
                    setStatus(string.format(u8"Загрузка... %d КБ", totalBytes / 1024), C.warning)
                end

                file:close()
            end)

            return success and doesFileExist(path)
        end

        setStatus(u8"Соединение с сервером...", C.warning)
        ok = tryJavaDownload()

        -- === МЕТОД 2: LuaSocket (fallback) ===
        if not ok then
            setStatus(u8"Попытка через сокет...", C.warning)
            local socketOk = pcall(require, "socket")
            local httpOk, http = pcall(require, "socket.http")
            local ltnOk, ltn12 = pcall(require, "ltn12")

            if socketOk and httpOk and ltnOk then
                local file = io.open(path, "wb")
                if file then
                    local sink = ltn12.sink.file(file)
                    local result, code = http.request{
                        url = url,
                        sink = sink,
                        headers = {
                            ["User-Agent"] = "Mozilla/5.0"
                        }
                    }
                    if result and code == 200 then
                        ok = true
                    else
                        pcall(function() file:close() end)
                    end
                end
            end
        end

        -- === МЕТОД 3: requests (если есть) ===
        if not ok then
            setStatus(u8"Попытка через requests...", C.warning)
            local reqOk, requests = pcall(require, "requests")
            if reqOk then
                local resOk, response = pcall(requests.get, url, {
                    headers = { ["User-Agent"] = "Mozilla/5.0" }
                })
                if resOk and response and response.status_code == 200 and response.text then
                    local file = io.open(path, "wb")
                    if file then
                        file:write(response.text)
                        file:close()
                        ok = true
                    end
                end
            end
        end

        -- === Проверка файла ===
        if doesFileExist(path) then
            local f = io.open(path, "rb")
            if f then
                local size = f:seek("end")
                f:close()
                if size and size > 20 then
                    ok = true
                else
                    os.remove(path)
                    ok = false
                end
            end
        end

        if callback then callback(ok) end
    end)
end

-- ============================================================
-- ЗАГРУЗКА И ЗАПУСК ОСНОВНОГО СКРИПТА
-- ============================================================
local function loadRemoteScript()
    downloadFile(SCRIPT_URL, SCRIPT_PATH, function(ok)
        if not ok then
            setStatus(u8"Ошибка загрузки!", C.error_red)
            isChecking = false
            return
        end

        lua_thread.create(function()
            setStatus(u8"Проверка кода...", C.warning)
            wait(200)

            -- Проверяем что код валиден
            local file = io.open(SCRIPT_PATH, "rb")
            if not file then
                setStatus(u8"Ошибка чтения!", C.error_red)
                isChecking = false
                return
            end
            local code = file:read("*a")
            file:close()

            local chunk, err = loadstring(code, "@check")
            if not chunk then
                setStatus(u8"Код содержит ошибки!", C.error_red)
                isChecking = false
                secureDelete(SCRIPT_PATH)
                code = nil
                collectgarbage("collect")
                return
            end
            chunk = nil
            code = nil
            collectgarbage("collect")

            setStatus(u8"Запуск скрипта...", C.warning)
            wait(300)

            -- Загружаем как отдельный скрипт через MoonLoader
            local loadedScript = script.load(SCRIPT_PATH)

            if not loadedScript then
                setStatus(u8"Ошибка запуска!", C.error_red)
                isChecking = false
                secureDelete(SCRIPT_PATH)
                return
            end

            setStatus(u8"Успешно активировано!", C.success)
            wait(600)

            -- Удаляем файл — скрипт уже в памяти
            secureDelete(SCRIPT_PATH)

            -- Двойная проверка
            wait(100)
            if doesFileExist(SCRIPT_PATH) then
                os.remove(SCRIPT_PATH)
            end

            loaderOpen[0] = false
            isLoaded      = true

            sampAddChatMessage("{4A9BFF}[Loader] {FFFFFF}Скрипт активирован!", 0xFFFFFF)

            -- Выгружаем лоадер
            wait(400)
            collectgarbage("collect")
            thisScript():unload()
        end)
    end)
end

-- ============================================================
-- ПРОВЕРКА КЛЮЧА
-- ============================================================
local function checkKey()
    if isChecking then return end

    local inputKey = ffi.string(keyBuffer)
    inputKey = inputKey:match("^%s*(.-)%s*$")

    if #inputKey == 0 then
        setStatus(u8"Введите ключ!", C.warning)
        return
    end

    isChecking = true
    setStatus(u8"Проверка ключа...", C.warning)

    lua_thread.create(function()
        wait(400)

        if inputKey == VALID_KEY then
            setStatus(u8"Ключ принят!", C.success)
            wait(400)
            loadRemoteScript()
        else
            setStatus(u8"Неверный ключ!", C.error_red)
            isChecking = false
            ffi.fill(keyBuffer, ffi.sizeof(keyBuffer))
        end
    end)
end

-- ============================================================
-- ЛОГОТИП
-- ============================================================
local function drawLogo(dl, x, y, time)
    local text = "EXECUTIONER"
    local ts = imgui.CalcTextSize(text)
    local lx = x - ts.x / 2
    local glowA = 0.45 + math.sin(time * 3) * 0.15

    for r = 2, 1, -1 do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    dl:AddText(imgui.ImVec2(lx + dx, y + dy),
                        cU32(imgui.ImVec4(0.35, 0.65, 1.0, glowA * (3 - r) / 3 * 0.6)), text)
                end
            end
        end
    end
    dl:AddText(imgui.ImVec2(lx, y), cU32(imgui.ImVec4(1, 1, 1, 1)), text)

    local sub = "LOADER v1.0"
    local subTs = imgui.CalcTextSize(sub)
    dl:AddText(imgui.ImVec2(x - subTs.x / 2, y + ts.y + 4),
        cU32(imgui.ImVec4(0.50, 0.75, 1.0, 0.7)), sub)
end

-- ============================================================
-- ОКНО ЛОАДЕРА
-- ============================================================
imgui.OnFrame(
    function() return loaderOpen[0] and not isLoaded end,
    function(self)
        local time = os.clock()
        local sx, sy = getScreenResolution()

        local WW = 380 * S
        local WH = 280 * S

        imgui.SetNextWindowPos(imgui.ImVec2(sx / 2, sy / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(WW, WH), imgui.Cond.Always)

        imgui.PushStyleColor(imgui.Col.WindowBg, C.bg_window)
        imgui.PushStyleColor(imgui.Col.Border, C.border)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.5)

        imgui.Begin("##ExecLoader", nil,
            imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize +
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse +
            imgui.WindowFlags.NoMove)

        imgui.PopStyleColor(2)
        imgui.PopStyleVar(3)

        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local ws = imgui.GetWindowSize()

        -- Градиент сверху
        for i = 0, 60 do
            local a = (60 - i) / 60 * 0.15
            dl:AddRectFilled(
                imgui.ImVec2(wp.x, wp.y + i),
                imgui.ImVec2(wp.x + ws.x, wp.y + i + 1),
                cU32(imgui.ImVec4(0.30, 0.55, 0.95, a))
            )
        end

        -- Акцентная линия
        local lineW = 120 * S
        local lineX = wp.x + (ws.x - lineW) / 2
        for px = 0, lineW do
            local prog = px / lineW
            local a = 0.90 - math.abs(prog - 0.5) * 1.4
            if a > 0 then
                dl:AddLine(
                    imgui.ImVec2(lineX + px, wp.y),
                    imgui.ImVec2(lineX + px, wp.y + 2.5),
                    cU32(imgui.ImVec4(0.40, 0.70, 1.0, a))
                )
            end
        end

        drawLogo(dl, wp.x + ws.x / 2, wp.y + 30 * S, time)

        dl:AddLine(
            imgui.ImVec2(wp.x + 40, wp.y + 78 * S),
            imgui.ImVec2(wp.x + ws.x - 40, wp.y + 78 * S),
            cU32(imgui.ImVec4(1, 1, 1, 0.10)), 1
        )

        local hint = u8"Введите активационный ключ"
        local hintTs = imgui.CalcTextSize(hint)
        dl:AddText(
            imgui.ImVec2(wp.x + (ws.x - hintTs.x) / 2, wp.y + 92 * S),
            cU32(C.text_gray), hint
        )

        -- Поле ввода
        local inpW = 260 * S
        local inpX = (ws.x - inpW) / 2
        local inpY = 115 * S

        imgui.SetCursorPos(imgui.ImVec2(inpX, inpY))
        imgui.PushItemWidth(inpW)
        imgui.PushStyleColor(imgui.Col.FrameBg, C.bg_input)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.16, 0.19, 0.26, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.18, 0.22, 0.30, 1))
        imgui.PushStyleColor(imgui.Col.Border, C.accent)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(12 * S, 8 * S))

        local flags = imgui.InputTextFlags.EnterReturnsTrue + imgui.InputTextFlags.Password

        if imgui.InputTextWithHint("##keyinp", u8"Ключ...", keyBuffer, ffi.sizeof(keyBuffer), flags) then
            checkKey()
        end

        imgui.PopStyleVar(2)
        imgui.PopStyleColor(4)
        imgui.PopItemWidth()

        -- Кнопка
        local btnW = 260 * S
        local btnH = 36 * S
        local btnX = (ws.x - btnW) / 2
        local btnY = 165 * S

        imgui.SetCursorPos(imgui.ImVec2(btnX, btnY))
        local btnP = imgui.GetCursorScreenPos()
        local mp = imgui.GetMousePos()
        local btnHov = mp.x >= btnP.x and mp.x <= btnP.x + btnW and
                       mp.y >= btnP.y and mp.y <= btnP.y + btnH

        dl:AddRectFilled(
            imgui.ImVec2(btnP.x, btnP.y + 2),
            imgui.ImVec2(btnP.x + btnW, btnP.y + btnH + 2),
            cU32(imgui.ImVec4(0, 0, 0, 0.35)), 7
        )
        dl:AddRectFilled(
            btnP,
            imgui.ImVec2(btnP.x + btnW, btnP.y + btnH),
            cU32(btnHov and C.bg_button_h or C.bg_button), 7
        )
        dl:AddRect(
            btnP,
            imgui.ImVec2(btnP.x + btnW, btnP.y + btnH),
            cU32(imgui.ImVec4(0.55, 0.80, 1.0, 0.55)), 7, 15, 1.2
        )
        dl:AddRectFilled(
            imgui.ImVec2(btnP.x + 2, btnP.y + 1),
            imgui.ImVec2(btnP.x + btnW - 2, btnP.y + 3),
            cU32(imgui.ImVec4(1, 1, 1, 0.20)), 3
        )

        local btnText = isChecking and u8"Загрузка..." or u8"Активировать"
        local btnTs = imgui.CalcTextSize(btnText)
        dl:AddText(
            imgui.ImVec2(btnP.x + (btnW - btnTs.x) / 2, btnP.y + (btnH - btnTs.y) / 2),
            cU32(imgui.ImVec4(1, 1, 1, 1)), btnText
        )

        if imgui.InvisibleButton("##loadbtn", imgui.ImVec2(btnW, btnH)) then
            if not isChecking then
                checkKey()
            end
        end

        -- ============================================
        -- СТАТУС (с обрезанием длинного текста)
        -- ============================================
        if #statusText > 0 then
            local displayText = statusText
            -- Обрезаем если слишком длинный
            local maxW = ws.x - 30
            local stTs = imgui.CalcTextSize(displayText)
            if stTs.x > maxW then
                while imgui.CalcTextSize(displayText .. "..").x > maxW and #displayText > 3 do
                    displayText = displayText:sub(1, -2)
                end
                displayText = displayText .. ".."
                stTs = imgui.CalcTextSize(displayText)
            end

            -- Фон для статуса (подложка)
            local stX = wp.x + (ws.x - stTs.x) / 2
            local stY = wp.y + 220 * S

            dl:AddRectFilled(
                imgui.ImVec2(stX - 8, stY - 3),
                imgui.ImVec2(stX + stTs.x + 8, stY + stTs.y + 3),
                cU32(imgui.ImVec4(statusColor.x * 0.15, statusColor.y * 0.15, statusColor.z * 0.15, 0.6)),
                4
            )

            dl:AddText(
                imgui.ImVec2(stX, stY),
                cU32(statusColor), displayText
            )
        end

        local foot = "© ExecutionerMod"
        local footTs = imgui.CalcTextSize(foot)
        dl:AddText(
            imgui.ImVec2(wp.x + (ws.x - footTs.x) / 2, wp.y + ws.y - 20 * S),
            cU32(C.text_dim), foot
        )

        imgui.ShowCursor = true
        imgui.End()
    end
)

-- ============================================================
-- MAIN
-- ============================================================
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    -- Проверка/удаление старого файла если завис
    if doesFileExist(SCRIPT_PATH) then
        secureDelete(SCRIPT_PATH)
    end

    sampAddChatMessage("{4A9BFF}[Loader] {FFFFFF}Введите ключ для активации.", 0xFFFFFF)

    while true do
        wait(0)
        if isLoaded then
            imgui.ShowCursor = false
        else
            imgui.ShowCursor = loaderOpen[0]
        end
    end
end
