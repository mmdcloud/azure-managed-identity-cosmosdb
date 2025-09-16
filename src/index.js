require("dotenv").config();
const { DefaultAzureCredential, ManagedIdentityCredential } = require("@azure/identity");
const express = require("express");
const bodyParser = require("body-parser");
const { CosmosClient } = require("@azure/cosmos");

const credential = new DefaultAzureCredential();
const app = express();
app.use(bodyParser.json());

// Cosmos DB setup
const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  aadCredentials: credential
});
const database = client.database(process.env.COSMOS_DATABASE);
const container = database.container(process.env.COSMOS_CONTAINER);

// CREATE
app.post("/items", async (req, res) => {
  try {
    const { resource } = await container.items.create(req.body);
    res.status(201).json(resource);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// READ ALL
app.get("/items", async (req, res) => {
  try {
    const { resources } = await container.items.readAll().fetchAll();
    res.json(resources);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// READ ONE
app.get("/items/:id", async (req, res) => {
  try {
    const { resource } = await container.item(req.params.id, req.params.id).read();
    res.json(resource);
  } catch (err) {
    res.status(404).json({ error: "Item not found" });
  }
});

// UPDATE
app.put("/items/:id", async (req, res) => {
  try {
    const updatedItem = { ...req.body, id: req.params.id };
    const { resource } = await container.items.upsert(updatedItem);
    res.json(resource);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE
app.delete("/items/:id", async (req, res) => {
  try {
    await container.item(req.params.id, req.params.id).delete();
    res.json({ status: "deleted" });
  } catch (err) {
    res.status(404).json({ error: "Item not found" });
  }
});

const PORT = 8080;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));