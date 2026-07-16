local AIClient = {}
AIClient.__index = AIClient

local function isTable(value)
    return type(value) == "table"
end

local function isString(value)
    return type(value) == "string"
end

local function sleep(seconds)
    if task and type(task.wait) == "function" then
        task.wait(seconds)
    elseif os and os.clock then
        local start = os.clock()
        while os.clock() - start < seconds do
        end
    end
end

local function sanitizeText(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function truncateHistory(history, limit)
    while #history > limit do
        table.remove(history, 1)
    end
end

local function createPromise(executor)
    local promise = {
        state = "pending",
        value = nil,
        error = nil,
        handlers = {},
    }

    function promise:Resolve(value)
        if self.state ~= "pending" then
            return
        end
        self.state = "fulfilled"
        self.value = value
        for _, handler in ipairs(self.handlers) do
            if handler.onFulfilled then
                local ok, result = pcall(handler.onFulfilled, value)
                if not ok then
                    self:Reject(result)
                    break
                end
            end
        end
    end

    function promise:Reject(errorValue)
        if self.state ~= "pending" then
            return
        end
        self.state = "rejected"
        self.error = errorValue
        for _, handler in ipairs(self.handlers) do
            if handler.onRejected then
                local ok, result = pcall(handler.onRejected, errorValue)
                if not ok then
                    self.error = result
                end
            end
        end
    end

    function promise:Then(onFulfilled)
        if self.state == "fulfilled" then
            local ok, result = pcall(onFulfilled, self.value)
            if not ok then
                self:Reject(result)
            end
            return self
        end
        table.insert(self.handlers, { onFulfilled = onFulfilled })
        return self
    end

    function promise:Catch(onRejected)
        if self.state == "rejected" then
            local ok, result = pcall(onRejected, self.error)
            if not ok then
                self.error = result
            end
            return self
        end
        table.insert(self.handlers, { onRejected = onRejected })
        return self
    end

    function promise:Await()
        if self.state == "fulfilled" then
            return self.value, nil
        end
        if self.state == "rejected" then
            return nil, self.error
        end
        while self.state == "pending" do
            sleep(0.01)
        end
        if self.state == "fulfilled" then
            return self.value, nil
        end
        return nil, self.error
    end

    local ok, err = pcall(executor, promise)
    if not ok then
        promise:Reject(err)
    end

    return promise
end

function AIClient.new(url, options)
    local self = setmetatable({}, AIClient)
    options = options or {}

    self.url = string.gsub(url or "", "/+$", "")
    self.history = {}
    self.systemPrompt = options.systemPrompt or "Você é um assistente útil e objetivo."
    self.temperature = options.temperature or 0.7
    self.model = options.model or "default"
    self.maxHistory = options.maxHistory or 20
    self.maxRetries = options.maxRetries or 2
    self.timeout = options.timeout or 15
    self.cache = {}
    self.cacheEnabled = options.cache ~= false
    self.cacheMaxEntries = options.cacheMaxEntries or 100
    self.retryDelay = options.retryDelay or 0.5
    self.lastError = nil
    self.lastResponse = nil

    if self.url == "" then
        error("AIClient.new requires a backend URL")
    end

    return self
end

function AIClient:SetSystemPrompt(prompt)
    if isString(prompt) then
        self.systemPrompt = prompt
    end
    return self
end

function AIClient:SetTemperature(number)
    if type(number) == "number" then
        self.temperature = number
    end
    return self
end

function AIClient:SetModel(model)
    if isString(model) then
        self.model = model
    end
    return self
end

function AIClient:ClearHistory()
    self.history = {}
    return self
end

function AIClient:_BuildPayload(message)
    local payload = {
        message = sanitizeText(message),
        history = {},
        systemPrompt = self.systemPrompt,
        temperature = self.temperature,
        model = self.model,
    }

    local historySnapshot = {}
    for _, entry in ipairs(self.history) do
        table.insert(historySnapshot, {
            role = entry.role,
            content = sanitizeText(entry.content),
        })
    end

    payload.history = historySnapshot
    return payload
end

function AIClient:_NormalizeResponse(payload)
    if not isTable(payload) then
        return nil, "Resposta inválida do backend"
    end

    if payload.success ~= true then
        return nil, payload.error or "Erro desconhecido"
    end

    local responseText = payload.response
    if responseText == nil then
        return nil, "Resposta vazia"
    end

    responseText = sanitizeText(responseText)
    if responseText == "" then
        return nil, "Resposta vazia"
    end

    return responseText, nil
end

function AIClient:_SendRequest(payload)
    local HttpService = nil
    if game and typeof(game.GetService) == "function" then
        HttpService = game:GetService("HttpService")
    end

    local requestBody = nil
    local parseJson = nil
    local requestFn = nil

    if syn and type(syn.request) == "function" then
        requestFn = syn.request
        parseJson = function(value)
            return game and game:GetService("HttpService"):JSONDecode(value)
        end
    elseif http and type(http.request) == "function" then
        requestFn = http.request
        parseJson = function(value)
            return game and game:GetService("HttpService"):JSONDecode(value)
        end
    elseif HttpService and HttpService.RequestAsync and HttpService.JSONEncode and HttpService.JSONDecode then
        requestFn = function(request)
            return HttpService:RequestAsync(request)
        end
        requestBody = HttpService:JSONEncode(payload)
        parseJson = function(value)
            return HttpService:JSONDecode(value)
        end
    else
        return nil, "Nenhuma API HTTP suportada foi encontrada"
    end

    local request = {
        Url = self.url .. "/chat",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
        },
        Body = requestBody or (HttpService and HttpService:JSONEncode(payload)) or nil,
    }

    if requestFn == syn.request or requestFn == http.request then
        request.Body = requestBody or (HttpService and HttpService:JSONEncode(payload)) or nil
        request.Headers = request.Headers or {}
    end

    local result = nil
    local requestDone = false
    local requestThread = coroutine.create(function()
        local ok, response = pcall(function()
            return requestFn(request)
        end)
        if ok then
            result = response
        else
            result = { ok = false, error = response }
        end
        requestDone = true
    end)

    coroutine.resume(requestThread)
    local start = os.clock()
    while not requestDone and (os.clock() - start) < self.timeout do
        sleep(0.05)
    end

    if not requestDone then
        return nil, "Timeout na requisição"
    end

    if result == nil then
        return nil, "Resposta vazia"
    end

    if result.ok == false then
        return nil, result.error or "Falha na comunicação"
    end

    local responseBody = result.Body or result.body or result
    if isString(responseBody) then
        local ok, decoded = pcall(function()
            return parseJson(responseBody)
        end)
        if ok then
            return decoded, nil
        end
        return nil, "Resposta inválida do backend"
    end

    return responseBody, nil
end

function AIClient:_CacheKey(message)
    return string.lower(string.gsub(message or "", "%s+", " "))
end

function AIClient:_StoreCache(key, response)
    if not self.cacheEnabled then
        return
    end

    self.cache[key] = response
    if table.getn(self.cache) > self.cacheMaxEntries then
        local oldestKey = nil
        for cacheKey in pairs(self.cache) do
            oldestKey = cacheKey
            break
        end
        if oldestKey then
            self.cache[oldestKey] = nil
        end
    end
end

function AIClient:_GetCachedResponse(message)
    if not self.cacheEnabled then
        return nil
    end
    return self.cache[self:_CacheKey(message)]
end

function AIClient:_AppendHistory(message, responseText)
    table.insert(self.history, { role = "user", content = message })
    table.insert(self.history, { role = "assistant", content = responseText })
    truncateHistory(self.history, self.maxHistory)
end

function AIClient:Ask(message, callback)
    if not isString(message) or string.gsub(message, "%s+", "") == "" then
        local errorMessage = "Mensagem inválida"
        if callback then
            callback(errorMessage)
        end
        return createPromise(function(promise)
            promise:Reject(errorMessage)
        end)
    end

    local cached = self:_GetCachedResponse(message)
    if cached then
        if callback then
            callback(cached)
        end
        return createPromise(function(promise)
            promise:Resolve(cached)
        end)
    end

    local promise = createPromise(function(promise)
        local lastError = nil
        local lastResponse = nil

        for attempt = 1, self.maxRetries + 1 do
            local payload = self:_BuildPayload(message)
            local rawResponse, errorMessage = self:_SendRequest(payload)
            if errorMessage then
                lastError = errorMessage
                if attempt <= self.maxRetries then
                    sleep(self.retryDelay)
                else
                    self.lastError = errorMessage
                    promise:Reject(errorMessage)
                    if callback then
                        callback(errorMessage)
                    end
                    return
                end
            else
                local responseText, validationError = self:_NormalizeResponse(rawResponse)
                if validationError then
                    lastError = validationError
                    if attempt <= self.maxRetries then
                        sleep(self.retryDelay)
                    else
                        self.lastError = validationError
                        promise:Reject(validationError)
                        if callback then
                            callback(validationError)
                        end
                        return
                    end
                else
                    self.lastError = nil
                    self.lastResponse = responseText
                    self:_AppendHistory(message, responseText)
                    self:_StoreCache(self:_CacheKey(message), responseText)
                    promise:Resolve(responseText)
                    if callback then
                        callback(responseText)
                    end
                    return
                end
            end
        end

        if lastError then
            self.lastError = lastError
            promise:Reject(lastError)
            if callback then
                callback(lastError)
            end
        end
    end)

    return promise
end

return AIClient
