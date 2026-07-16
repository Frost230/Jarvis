local HttpService = nil
if type(game) == "userdata" and type(game.GetService) == "function" then
    HttpService = game:GetService("HttpService")
end

local APIConfig = {
    BaseURL = "https://jarvis-ecru-three.vercel.app",
    Timeout = 30,
    MaxRetries = 2,
    Model = "openai/gpt-oss-120b",
    ApiKey = ""
}

local function DeveUsarApiKey()
    return type(APIConfig.ApiKey) == "string" and APIConfig.ApiKey ~= ""
end
local ApiPronta = false

local function JsonEncode(value)
    if HttpService then
        return HttpService:JSONEncode(value)
    end
    error("JSONEncode não está disponível")
end

local function JsonDecode(value)
    if HttpService then
        return HttpService:JSONDecode(value)
    end
    error("JSONDecode não está disponível")
end

local function SendHttpRequest(url, payload)
    local body = JsonEncode(payload)
    local requestArgs = {
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = body
    }

    if syn and type(syn.request) == "function" then
        return syn.request(requestArgs)
    elseif http and type(http.request) == "function" then
        return http.request(requestArgs)
    elseif HttpService and HttpService.RequestAsync then
        requestArgs.Timeout = APIConfig.Timeout
        return HttpService:RequestAsync(requestArgs)
    end

    return nil, "Nenhuma API HTTP suportada"
end

local MemoriaIA = {
    Historico = {},
    MaxMensagens = 40,
    Contexto = "Você é uma assistente útil, amigável e objetiva. Responde em português brasileiro e ajuda com Roblox, programação e conversas gerais."
}

local CacheRespostas = {}
local Interface = {
    ScreenGui = nil,
    MainFrame = nil,
    ScrollFrame = nil,
    InputBox = nil,
    StatusLabel = nil
}

local function LimparEspacos(texto)
    if type(texto) ~= "string" then
        return ""
    end
    texto = string.gsub(texto, "^%s+", "")
    texto = string.gsub(texto, "%s+$", "")
    return texto
end

local function ParseResponse(response)
    if type(response) ~= "table" then
        return nil, nil, "Resposta inválida do backend"
    end

    if response.Success == false and response.Body == nil then
        return nil, nil, response.Error or response.StatusMessage or "Falha na requisição"
    end

    local statusCode = response.StatusCode or response.status or response.code or response.status_code
    local body = response.Body or response.body

    if not statusCode then
        return nil, nil, "Status inválido do backend"
    end

    return statusCode, body, nil
end

local function FazerRequisicao(payload, retryCount)
    retryCount = retryCount or 0
    local url = string.gsub(APIConfig.BaseURL, "/+$", "") .. "/chat"

    local response, err = SendHttpRequest(url, payload)
    if not response then
        if retryCount < APIConfig.MaxRetries then
            wait(2 ^ retryCount)
            return FazerRequisicao(payload, retryCount + 1)
        end
        return nil, err or "Erro de conexão com o backend"
    end

    local statusCode, body, parseErr = ParseResponse(response)
    if not statusCode then
        return nil, parseErr
    end

    local ok, data = pcall(function()
        return JsonDecode(body)
    end)

    if not ok or type(data) ~= "table" then
        return nil, "Resposta inválida do backend"
    end

    if statusCode == 200 and data.success == true and type(data.response) == "string" and data.response ~= "" then
        return data.response, nil
    end

    if data.error and type(data.error) == "string" and data.error ~= "" then
        return nil, data.error
    end

    if statusCode == 400 then
        return nil, "Requisição inválida para o backend"
    elseif statusCode == 404 then
        return nil, "Rota /chat não encontrada no backend"
    elseif statusCode == 500 then
        return nil, "Erro interno no backend"
    end

    return nil, data.error or body or "Erro desconhecido do backend"
end

function PerguntarIA(mensagem, callback)
    mensagem = LimparEspacos(mensagem)
    if mensagem == "" then
        callback(nil, "Mensagem vazia")
        return
    end

    local cacheKey = string.lower(string.sub(string.gsub(mensagem, "%s+", " "), 1, 120))
    if CacheRespostas[cacheKey] then
        callback(CacheRespostas[cacheKey], nil)
        return
    end

    table.insert(MemoriaIA.Historico, { role = "user", content = mensagem })
    if #MemoriaIA.Historico > MemoriaIA.MaxMensagens then
        table.remove(MemoriaIA.Historico, 1)
    end

    local historySnapshot = {}
    local startIndex = math.max(1, #MemoriaIA.Historico - 10)
    for i = startIndex, #MemoriaIA.Historico do
        local entry = MemoriaIA.Historico[i]
        if entry then
            table.insert(historySnapshot, {
                role = entry.role,
                content = entry.content
            })
        end
    end

    local payload = {
        message = mensagem,
        history = historySnapshot,
        systemPrompt = MemoriaIA.Contexto,
        temperature = 0.8,
        model = APIConfig.Model,
        apiKey = APIConfig.ApiKey
    }

    local resposta, erro = FazerRequisicao(payload)

    if resposta then
        CacheRespostas[cacheKey] = resposta
        table.insert(MemoriaIA.Historico, { role = "assistant", content = resposta })
        callback(resposta, nil)
    else
        callback(nil, erro or "Erro ao processar sua mensagem")
    end
end

function LimparMemoria()
    MemoriaIA.Historico = {}
    CacheRespostas = {}
    return "Memória limpa"
end

function TestarConexao(callback)
    local payload = {
        message = "Teste de conexão. Você está funcionando?",
        history = {},
        systemPrompt = MemoriaIA.Contexto,
        temperature = 0.1,
        model = APIConfig.Model,
        apiKey = APIConfig.ApiKey
    }

    local resposta, erro = FazerRequisicao(payload)
    if resposta then
        callback(true, resposta)
    else
        callback(false, erro or "Falha na conexão")
    end
end

function AdicionarMensagem(texto, isUser)
    if not Interface.ScrollFrame then
        return
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -12, 0, 0)
    frame.BackgroundTransparency = 1
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Parent = Interface.ScrollFrame

    local bubble = Instance.new("Frame")
    bubble.Size = UDim2.new(0.95, 0, 0, 0)
    bubble.AutomaticSize = Enum.AutomaticSize.Y
    bubble.BackgroundColor3 = isUser and Color3.fromRGB(55, 95, 170) or Color3.fromRGB(26, 26, 38)
    bubble.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = bubble

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -12, 0, 0)
    label.Position = UDim2.new(0, 6, 0, 4)
    label.BackgroundTransparency = 1
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Text = (isUser and "Você: " or "IA: ") .. texto
    label.TextColor3 = isUser and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 220, 255)
    label.TextWrapped = true
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.Parent = bubble

    wait(0.03)
    Interface.ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, Interface.ScrollFrame.UIListLayout.AbsoluteContentSize.Y + 20)
    Interface.ScrollFrame.CanvasPosition = Vector2.new(0, Interface.ScrollFrame.CanvasSize.Y.Offset)
end

function AtualizarStatus(texto, cor)
    if Interface.StatusLabel then
        Interface.StatusLabel.Text = texto
        Interface.StatusLabel.TextColor3 = cor
    end
end

function CriarInterface()
    if Interface.ScreenGui then
        Interface.ScreenGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "StellwinAI_Executor"
    screenGui.Parent = game.CoreGui
    Interface.ScreenGui = screenGui

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 500, 0, 620)
    mainFrame.Position = UDim2.new(0.5, -250, 0.5, -310)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame
    Interface.MainFrame = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 46)
    title.BackgroundTransparency = 1
    title.Text = "StellwinAI • Executor"
    title.TextColor3 = Color3.fromRGB(120, 210, 255)
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 24)
    statusLabel.Position = UDim2.new(0, 0, 0, 44)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Aguardando..."
    statusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = mainFrame
    Interface.StatusLabel = statusLabel

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -18, 0, 470)
    scrollFrame.Position = UDim2.new(0, 9, 0, 78)
    scrollFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.Parent = mainFrame
    Interface.ScrollFrame = scrollFrame

    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 10)
    scrollCorner.Parent = scrollFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 6)
    listLayout.Parent = scrollFrame

    local inputBox = Instance.new("TextBox")
    inputBox.Size = UDim2.new(0.74, 0, 0, 42)
    inputBox.Position = UDim2.new(0, 10, 1, -54)
    inputBox.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
    inputBox.BorderSizePixel = 0
    inputBox.PlaceholderText = "Digite sua mensagem..."
    inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    inputBox.TextSize = 14
    inputBox.Font = Enum.Font.Gotham
    inputBox.Parent = mainFrame
    Interface.InputBox = inputBox

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 8)
    inputCorner.Parent = inputBox

    local sendBtn = Instance.new("TextButton")
    sendBtn.Size = UDim2.new(0.2, 0, 0, 42)
    sendBtn.Position = UDim2.new(0.77, 0, 1, -54)
    sendBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    sendBtn.BorderSizePixel = 0
    sendBtn.Text = "Enviar"
    sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    sendBtn.TextSize = 14
    sendBtn.Font = Enum.Font.GothamBold
    sendBtn.Parent = mainFrame

    local sendCorner = Instance.new("UICorner")
    sendCorner.CornerRadius = UDim.new(0, 8)
    sendCorner.Parent = sendBtn

    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0.2, 0, 0, 34)
    clearBtn.Position = UDim2.new(0.77, 0, 1, -96)
    clearBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
    clearBtn.BorderSizePixel = 0
    clearBtn.Text = "Limpar"
    clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    clearBtn.TextSize = 13
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.Parent = mainFrame

    local clearCorner = Instance.new("UICorner")
    clearCorner.CornerRadius = UDim.new(0, 8)
    clearCorner.Parent = clearBtn

    local function EnviarUI()
        local texto = LimparEspacos(inputBox.Text)
        if texto ~= "" then
            inputBox.Text = ""
            EnviarMensagem(texto)
        end
    end

    sendBtn.MouseButton1Click:Connect(EnviarUI)
    clearBtn.MouseButton1Click:Connect(function()
        LimparMemoria()
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        AdicionarMensagem("Histórico limpo", false)
    end)

    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            EnviarUI()
        end
    end)
end

function EnviarMensagem(texto)
    if not ApiPronta then
        AdicionarMensagem("A conexão com o backend não está pronta. Verifique o status.", false)
        return
    end

    AdicionarMensagem(texto, true)
    AtualizarStatus("Pensando...", Color3.fromRGB(255, 215, 0))

    PerguntarIA(texto, function(resposta, erro)
        if resposta then
            AdicionarMensagem(resposta, false)
            AtualizarStatus("IA online", Color3.fromRGB(0, 255, 0))
        else
            AdicionarMensagem(erro or "Erro ao responder", false)
            AtualizarStatus("Erro", Color3.fromRGB(255, 70, 70))
        end
    end)
end

local function Iniciar()
    if not APIConfig.BaseURL or APIConfig.BaseURL == "" then
        warn("Defina a URL do backend no campo BaseURL")
        return
    end

    pcall(CriarInterface)
    wait(0.5)
    AdicionarMensagem("Olá! Sou a StellwinAI. Estou usando o backend /chat.", false)
    AtualizarStatus("Verificando chave/API no backend...", Color3.fromRGB(255, 215, 0))

    TestarConexao(function(ok, message)
        if ok then
            ApiPronta = true
            AdicionarMensagem("Conexão OK: " .. string.sub(message, 1, 120), false)
            AtualizarStatus("IA online", Color3.fromRGB(0, 255, 0))
        else
            ApiPronta = false
            local mensagemErro = message or "Falha na conexão"
            if DeveUsarApiKey() then
                AdicionarMensagem("Erro na chave/API: " .. mensagemErro, false)
            else
                AdicionarMensagem("Erro no backend: " .. mensagemErro, false)
            end
            AtualizarStatus("Erro na conexão", Color3.fromRGB(255, 70, 70))
        end
    end)
end

pcall(Iniciar)
print("StellwinAI carregada")
