#!/usr/bin/env node
/**
 * Verify the database deliverable end to end.
 *
 *   DATABASE_URL=postgresql://user@host:5432/db node database/tools/verify.js
 *
 * Applies every migration to a scratch schema, runs the integrity test suite,
 * and prints a machine-readable summary. Exit code is non-zero on any failure,
 * so CI can gate on it.
 *
 * Requirements: `pg` package (dev dependency) and an empty database the given
 * user may create schemas in. Never point this at a database with real PHI:
 * it drops the `aybak` schema.
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const MIGRATIONS = path.join(ROOT, "database", "migrations");
const TESTS = path.join(ROOT, "database", "tests", "schema_integrity.sql");

async function main() {
  let Client;
  try {
    ({ Client } = require("pg"));
  } catch (error) {
    console.error("Requires the 'pg' package: npm install --no-save pg");
    process.exit(2);
  }

  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error("Set DATABASE_URL to an empty, disposable database.");
    process.exit(2);
  }
  if (/prod|live|clinical/i.test(connectionString)) {
    console.error("Refusing to run: DATABASE_URL looks like a production database.");
    process.exit(2);
  }

  const client = new Client({ connectionString });
  await client.connect();

  try {
    await client.query(
      "DROP SCHEMA IF EXISTS aybak CASCADE; DROP EXTENSION IF EXISTS btree_gist; DROP EXTENSION IF EXISTS pgcrypto;"
    );

    const files = fs
      .readdirSync(MIGRATIONS)
      .filter((file) => file.endsWith(".sql"))
      .sort();

    for (const file of files) {
      const sql = fs.readFileSync(path.join(MIGRATIONS, file), "utf8");
      await client.query(sql);
      console.log(`migration OK   ${file}`);
    }

    const catalog = await client.query(`
      SELECT
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'aybak' AND c.relkind = 'r') AS tables,
        (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
          WHERE n.nspname = 'aybak' AND c.contype = 'f') AS foreign_keys,
        (SELECT count(*) FROM pg_indexes WHERE schemaname = 'aybak') AS indexes,
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'aybak' AND c.relkind = 'r' AND c.relrowsecurity) AS rls_tables
    `);
    console.log("catalog        " + JSON.stringify(catalog.rows[0]));

    // Run the test file without its final summary block and rollback, so that
    // individual results stay queryable for reporting.
    let tests = fs.readFileSync(TESTS, "utf8");
    tests = tests.replace(/DO \$\$\s*DECLARE v_total[\s\S]*?\$\$;\s*ROLLBACK;\s*$/, "");
    await client.query(tests);

    const results = await client.query("SELECT name, passed, detail FROM test_result ORDER BY seq");
    for (const row of results.rows) {
      console.log(`${row.passed ? "test PASS" : "test FAIL"}   ${row.name}${row.passed ? "" : " | " + row.detail}`);
    }
    const failed = results.rows.filter((row) => !row.passed).length;
    console.log(`\n${results.rows.length} assertions, ${failed} failed`);
    process.exitCode = failed === 0 ? 0 : 1;
  } catch (error) {
    console.error(`FAILED: ${error.message}`);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
}

main();
