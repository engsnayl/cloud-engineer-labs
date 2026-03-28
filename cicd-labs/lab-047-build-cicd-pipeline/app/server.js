const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

app.get('/api/items', (req, res) => {
  res.json([
    { id: 1, name: 'Widget A', status: 'active' },
    { id: 2, name: 'Widget B', status: 'active' },
    { id: 3, name: 'Widget C', status: 'inactive' }
  ]);
});

app.get('/api/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const items = [
    { id: 1, name: 'Widget A', status: 'active' },
    { id: 2, name: 'Widget B', status: 'active' },
    { id: 3, name: 'Widget C', status: 'inactive' }
  ];
  const item = items.find(i => i.id === id);
  if (!item) {
    return res.status(404).json({ error: 'Item not found' });
  }
  res.json(item);
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`API server running on port ${PORT}`);
  });
}

module.exports = app;
