local AIClient = require(script.Parent.AIClient)

local ai = AIClient.new("https://meu-backend.onrender.com")
ai:SetSystemPrompt("Você é um assistente útil e conciso.")
ai:SetTemperature(0.8)
ai:SetModel("gpt-4o-mini")

ai:Ask("Olá", function(response)
    print(response)
end)

local promise = ai:Ask("Explique o que é um cliente de IA em Roblox.")
promise:Then(function(response)
    print(response)
end):Catch(function(errorMessage)
    print(errorMessage)
end)
