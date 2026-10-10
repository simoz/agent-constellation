const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const protocol = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Protocol.js'), 'utf8'), protocol);

function agent(id) {
    return {id, kind: 'claude', name: 'demo', project: 'demo', model: 'opus-5-5', status: 'working', waitingFor: '',
        activity: {tool: 'Edit', target: 'app/a.rb', atMs: 1800000000000, subagent: ''}, toolCalls: 3, outputTokens: 120,
        tokensPerMinute: 40, activityBuckets: Array(30).fill(0), pids: [4242, 4200], subagents: [{id: 'agent-1', name: 'Explore', type: 'Explore'}],
        files: [{path: 'app/a.rb', touches: 2, edits: 1, added: 3, removed: 1, heat: 1, lastMs: 1800000000000, subagent: ''}]};
}
function snapshot() {
    return {version: 1, requestId: 'r-1', session: '0123456789abcdef', sequence: 1, observedAtMs: 1800000000000, status: 'ok',
        sources: {claude: 'ok', codex: 'missing'}, agents: [agent('claude:1')],
        events: [{atMs: 1800000000000, agent: 'claude:1', subagent: '', tool: 'Edit', target: 'app/a.rb'}]};
}
test('accepts a valid snapshot', () => {
    assert.equal(protocol.parse(JSON.stringify(snapshot()), 'r-1', '', 0).agents.length, 1);
});
test('rejects bad schema, late replies and repeated sequences', () => {
    const changes = [s => s.version = 2, s => s.requestId = 'late', s => s.agents[0].status = 'busy',
        s => s.agents[0].activityBuckets.pop(), s => s.agents[0].files[0].heat = 2, s => s.agents[0].name = 'bad\nname',
        s => s.events[0].agent = 'unknown', s => s.agents.push(s.agents[0]), s => s.sources.codex = 'maybe',
        s => s.error = 'boom', s => s.session = 'short', s => s.agents[0].pids = [1], s => s.agents[0].pids = Array(17).fill(9)];
    for (const change of changes) {
        const s = snapshot(); change(s);
        assert.throws(() => protocol.parse(JSON.stringify(s), 'r-1', '', 0), String(change));
    }
    assert.throws(() => protocol.parse(JSON.stringify(snapshot()), 'r-1', '0123456789abcdef', 1));
    const restarted = snapshot(); restarted.session = 'fedcba9876543210';
    assert.equal(protocol.parse(JSON.stringify(restarted), 'r-1', '0123456789abcdef', 7).sequence, 1);
});
test('frames one line at a time and rejects non-ASCII chunks', () => {
    let framed = protocol.frame('', '{"a":');
    assert.equal(framed.lines.length, 0);
    framed = protocol.frame(framed.buffer, '1}\n');
    assert.deepEqual(Array.from(framed.lines), ['{"a":1}']);
    assert.throws(() => protocol.frame('', 'é'));
    assert.throws(() => protocol.frame('', '{}\n{}\n'));
});
