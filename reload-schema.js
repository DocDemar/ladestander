require('dotenv').config();
const { Pool } = require('pg');
const db = new Pool({ connectionString: process.env.DATABASE_URL });
db.query("NOTIFY pgrst, 'reload schema'").then(() => {
  console.log('PostgREST schema reload sendt');
  db.end();
}).catch(e => { console.error(e.message); db.end(); });
