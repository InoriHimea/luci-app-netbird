// SPDX-License-Identifier: Apache-2.0
import { connect } from 'ubus';
const session_bus = connect(null, 2);
// SID remains only in the deferred closure. Never use a caller-supplied actor.
function authenticated_actor(handler, denied, allow_local_root) {
    return function(request) {
        let sid = request.args?.ubus_rpc_session;
        // This ACL comes from ubusd credentials, not request.args. Existing root
        // automation remains local-root; HTTP still requires its native session.
        if (sid == null && allow_local_root && request.info?.acl?.user == 'root')
            return handler(request, 'local-root');
        if (!session_bus || type(sid) != 'string' || !match(sid, /^[0-9a-f]{32}$/)) return denied();
        // A synchronous session.get in rpcd deadlocks its own session loop.
        return session_bus.defer('session', 'get', { ubus_rpc_session: sid }, function(code, session) {
            let actor = session?.values?.username;
            if (code != 0 || type(actor) != 'string' || !match(actor, /^[A-Za-z0-9_.@+-]{1,96}$/)) {
                request.reply(denied()); return;
            }
            request.reply(handler(request, actor));
        });
    };
}
export { authenticated_actor };
