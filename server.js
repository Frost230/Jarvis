const http = require('http');

const port = process.env.PORT || 3000;
let apiKey = process.env.GROQ_API_KEY || process.env.HF_API_KEY || '';
const defaultModel = 'openai/gpt-oss-120b';
const groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

function buildMessages(payload) {
  const history = Array.isArray(payload.history) ? payload.history : [];
  const messages = [];

  if (typeof payload.systemPrompt === 'string') {
    messages.push({ role: 'system', content: payload.systemPrompt });
  }

  for (const entry of history) {
    if (entry && entry.role && entry.content) {
      messages.push({ role: entry.role, content: entry.content });
    }
  }

  messages.push({ role: 'user', content: payload.message || '' });
  return messages;
}

async function getModelResponse(payload, key) {
  const response = await fetch(groqUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(errorText || `Falha na chamada ao Groq (${response.status})`);
  }

  return response.json();
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/chat') {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
    });

    req.on('end', async () => {
      try {
        const payload = JSON.parse(body || '{}');
        const message = payload.message || '';
        const key = payload.apiKey || apiKey;
        const model = payload.model || defaultModel;

        if (!message) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'Mensagem vazia' }));
          return;
        }

        if (!key || typeof key !== 'string' || key.trim() === '') {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'Chave da Groq não configurada' }));
          return;
        }

        if (!apiKey) {
          apiKey = key;
        }

        const requestBody = {
          model,
          messages: buildMessages(payload),
          temperature: payload.temperature || 0.8,
          max_tokens: payload.max_tokens || 500,
          top_p: payload.top_p || 0.95,
          stream: false,
        };

        const data = await getModelResponse(requestBody, key);
        const responseText = data?.choices?.[0]?.message?.content || '';

        if (typeof responseText !== 'string' || responseText === '') {
          throw new Error('Resposta inválida do Groq');
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, response: responseText }));
      } catch (error) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: error.message || 'Erro interno' }));
      }
    });

    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ success: false, error: 'Rota não encontrada' }));
});

server.listen(port, () => {
  console.log(`Backend de exemplo ouvindo em http://localhost:${port}`);
});
