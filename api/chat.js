const defaultModel = 'openai/gpt-oss-120b';
const groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

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

function parseBody(req) {
  if (req.body && typeof req.body === 'string') {
    try {
      return JSON.parse(req.body);
    } catch {
      return {};
    }
  }

  if (req.body && typeof req.body === 'object') {
    return req.body;
  }

  return {};
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);

  if (req.method === 'OPTIONS') {
    res.status(200).end('');
    return;
  }

  if (req.method === 'GET') {
    res.status(200).json({ success: true, message: 'Jarvis backend está online' });
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ success: false, error: 'Método não permitido' });
    return;
  }

  const payload = parseBody(req);
  const message = payload.message || '';
  const key = (typeof payload.apiKey === 'string' && payload.apiKey.trim() !== '')
    ? payload.apiKey
    : (process.env.GROQ_API_KEY || process.env.HF_API_KEY || '');
  const model = payload.model || defaultModel;

  if (!message) {
    res.status(400).json({ success: false, error: 'Mensagem vazia' });
    return;
  }

  if (!key) {
    res.status(500).json({ success: false, error: 'Chave da Groq não configurada' });
    return;
  }

  try {
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

    res.status(200).json({ success: true, response: responseText });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message || 'Erro interno' });
  }
};
