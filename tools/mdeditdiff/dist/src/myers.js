// Myers' O((N+M)D) shortest-edit-script diff over two sequences of strings.
// Common prefix and suffix are trimmed first; if the edit distance is very large,
// the middle falls back to "delete all, insert all" so huge rewrites stay fast.
const MAX_D = 4000;
export function diffSeq(a, b) {
    let pre = 0;
    while (pre < a.length && pre < b.length && a[pre] === b[pre])
        pre++;
    let suf = 0;
    while (suf < a.length - pre && suf < b.length - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf])
        suf++;
    const out = [];
    for (let k = 0; k < pre; k++)
        out.push({ op: "equal", a: k, b: k });
    const midA = a.slice(pre, a.length - suf);
    const midB = b.slice(pre, b.length - suf);
    for (const o of middle(midA, midB))
        out.push({ op: o.op, a: o.a + pre, b: o.b + pre });
    for (let k = suf; k > 0; k--)
        out.push({ op: "equal", a: a.length - k, b: b.length - k });
    return out;
}
function middle(a, b) {
    const n = a.length;
    const m = b.length;
    if (n === 0)
        return b.map((_, j) => ({ op: "insert", a: 0, b: j }));
    if (m === 0)
        return a.map((_, i) => ({ op: "delete", a: i, b: 0 }));
    const max = n + m;
    const offset = max;
    let v = new Int32Array(2 * max + 2);
    const trace = [];
    let found = -1;
    for (let d = 0; d <= Math.min(max, MAX_D); d++) {
        trace.push(v.slice());
        for (let k = -d; k <= d; k += 2) {
            let x;
            if (k === -d || (k !== d && v[offset + k - 1] < v[offset + k + 1]))
                x = v[offset + k + 1];
            else
                x = v[offset + k - 1] + 1;
            let y = x - k;
            while (x < n && y < m && a[x] === b[y]) {
                x++;
                y++;
            }
            v[offset + k] = x;
            if (x >= n && y >= m) {
                found = d;
                break;
            }
        }
        if (found >= 0) {
            trace.push(v.slice());
            break;
        }
    }
    if (found < 0) {
        return [
            ...a.map((_, i) => ({ op: "delete", a: i, b: 0 })),
            ...b.map((_, j) => ({ op: "insert", a: n, b: j })),
        ];
    }
    // Backtrack. trace[d] holds V before step d; trace[found+1] holds the final V.
    const ops = [];
    let x = n;
    let y = m;
    for (let d = found; d >= 0; d--) {
        const vd = trace[d];
        const k = x - y;
        let prevK;
        if (d === 0)
            prevK = 0;
        else if (k === -d || (k !== d && vd[offset + k - 1] < vd[offset + k + 1]))
            prevK = k + 1;
        else
            prevK = k - 1;
        const prevX = d === 0 ? 0 : vd[offset + prevK];
        const prevY = prevX - prevK;
        while (x > prevX && y > prevY) {
            x--;
            y--;
            ops.push({ op: "equal", a: x, b: y });
        }
        if (d > 0) {
            if (x === prevX) {
                y--;
                ops.push({ op: "insert", a: x, b: y });
            }
            else {
                x--;
                ops.push({ op: "delete", a: x, b: y });
            }
        }
    }
    return ops.reverse();
}
