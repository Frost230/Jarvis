# AIClient para Roblox

Este projeto fornece um cliente LuaU modular para consumir um backend de IA em Roblox.

## Arquivos
- AIClient.lua: módulo principal com histórico, retry, timeout, cache e tratamento de erros.
- example.lua: exemplo de uso em um Script do Roblox.
- index.html: página HTML simples para testar o endpoint diretamente no navegador.

## Uso rápido
```lua
local AIClient = require(script.Parent.AIClient)
local ai = AIClient.new("https://jarvis-ecru-three.vercel.app")

ai:Ask("Olá", function(response)
    print(response)
end)
```

## Deploy no Vercel
1. Crie um projeto no Vercel e conecte este repositório.
2. Adicione a variável de ambiente `GROQ_API_KEY` com sua chave válida.
3. Faça o deploy; a rota `/chat` estará disponível em `https://<seu-projeto>.vercel.app/chat`.
