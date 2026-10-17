// mdeditdiff as an MCP server over standard input and output.
// Tools are read-and-record only: none of them changes a document.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { changesSince, checkpoint, diffRevisions, history, markSeen, showRevision } from "./api.js";
import { renderChanges, renderDiff, renderHistory, renderRevision } from "./format.js";
import { Store, UserError } from "./store.js";
import { VERSION } from "./version.js";
function run(fn, asJson) {
    try {
        const { data, text } = fn();
        return { content: [{ type: "text", text: asJson ? JSON.stringify(data, null, 2) : text }] };
    }
    catch (e) {
        const msg = e instanceof UserError ? e.message : `Unexpected error: ${e.message}`;
        return { content: [{ type: "text", text: msg }], isError: true };
    }
}
const file = z.string().describe("Path to the Markdown file. Relative paths resolve against the server's working directory.");
const reader = z
    .string()
    .describe("Your stable reader name, for example 'planner' or 'implementer'. Each reader has its own 'last looked' point.");
const json = z.boolean().optional().describe("Return JSON (docs/FORMAT.md) instead of compact text.");
const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: false, openWorldHint: false };
export function createServer(storeDir) {
    const store = new Store(storeDir);
    const server = new McpServer({ name: "mdeditdiff", version: VERSION }, {
        instructions: "mdeditdiff tells you what changed in a shared Markdown file since you last looked, and who changed it. " +
            "Before working from a shared plan or spec, call changes_since with a stable reader name instead of re-reading the whole file. " +
            "After you edit the file, call checkpoint with your name and a one-line note so the next reader knows what you changed. " +
            "These tools never modify files.",
    });
    server.registerTool("changes_since", {
        title: "What changed since I last looked",
        description: "Return the changes to a Markdown file since this reader last looked: added, removed and modified blocks with section, " +
            "old and new text, and which revisions (and reported authors) they came from. The first call for a reader returns the full text. " +
            "By default the current version is then marked as seen.",
        inputSchema: {
            path: file,
            reader,
            mark_seen: z.boolean().optional().describe("Mark the current version as seen (default true). Use false to peek."),
            full: z.boolean().optional().describe("Also return the full current text."),
            json,
        },
        annotations: readOnly,
    }, ({ path, reader, mark_seen, full, json }) => run(() => {
        const r = changesSince(store, path, reader, { markSeen: mark_seen ?? true, full });
        return { data: r, text: renderChanges(r) };
    }, json));
    server.registerTool("mark_seen", {
        title: "Mark as seen",
        description: "Set this reader's 'last looked' point to the current version of the file.",
        inputSchema: { path: file, reader },
        annotations: readOnly,
    }, ({ path, reader }) => run(() => {
        const r = markSeen(store, path, reader);
        return { data: r, text: `Marked ${r.seen.revision} as seen for "${r.reader}".` };
    }));
    server.registerTool("checkpoint", {
        title: "Record my change",
        description: "Record the file's current version with your name and a short note, so other readers see who changed what. " +
            "Call it right after you edit the file. Authorship is self-reported.",
        inputSchema: {
            path: file,
            author: z.string().describe("Your name as other readers should see it, for example 'planner'."),
            note: z.string().max(500).optional().describe("One line on what you changed and why."),
        },
        annotations: readOnly,
    }, ({ path, author, note }) => run(() => {
        const r = checkpoint(store, path, author, note);
        return { data: r, text: `${r.revision.revision}: ${r.message}` };
    }));
    server.registerTool("history", {
        title: "Revision history",
        description: "List the file's revisions, newest first, with reported authors and notes, and where each reader last looked.",
        inputSchema: { path: file, limit: z.number().int().min(1).max(500).optional(), json },
        annotations: readOnly,
    }, ({ path, limit, json }) => run(() => {
        const r = history(store, path, limit ?? 50);
        return { data: r, text: renderHistory(r) };
    }, json));
    server.registerTool("diff", {
        title: "Compare two revisions",
        description: "Compare two revisions of the file, for example from 'r3' to 'r7' or to 'latest'.",
        inputSchema: { path: file, from: z.string(), to: z.string().optional().describe("Defaults to 'latest'."), json },
        annotations: readOnly,
    }, ({ path, from, to, json }) => run(() => {
        const r = diffRevisions(store, path, from, to ?? "latest");
        return { data: r, text: renderDiff(r) };
    }, json));
    server.registerTool("get_revision", {
        title: "Get a revision",
        description: "Return the full text of one revision, for example to recover something that was removed.",
        inputSchema: { path: file, revision: z.string().describe("For example 'r3' or 'latest'.") },
        annotations: readOnly,
    }, ({ path, revision }) => run(() => {
        const r = showRevision(store, path, revision);
        return { data: r, text: renderRevision(r) };
    }));
    return server;
}
export async function serve(storeDir) {
    const server = createServer(storeDir);
    await server.connect(new StdioServerTransport());
}
