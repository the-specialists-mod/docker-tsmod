// amxx-testenv: fakemeta private-data read on a player. CBasePlayer pdata offsets are
// mp.dll's (C++) layout; the port's private data is a small Rust allocation, so offset 100
// (+5 ints linuxdiff on Linux) reads past it. Logs to addons/amxmodx/logs/pdata_test.log.
// Runs 20 s after map start and on the server command pdata_test.
#include <amxmodx>
#include <fakemeta>

new const LOG[] = "pdata_test.log";

public plugin_init()
{
	register_plugin("pdata_test", "0.1", "amxx-testenv");
	register_srvcmd("pdata_test", "cmd_test");
	log_to_file(LOG, "plugin_init");
	set_task(20.0, "run");
}

public cmd_test()
{
	run();
	return PLUGIN_HANDLED;
}

public run()
{
	new players[32], n;
	get_players(players, n);
	log_to_file(LOG, "run: %d players", n);
	for (new i = 0; i < n; i++)
	{
		new id = players[i];
		log_to_file(LOG, "  id=%d pev_valid=%d (2 = has private data); calling get_pdata_int(id, 100)", id, pev_valid(id));
		new v = get_pdata_int(id, 100);
		log_to_file(LOG, "  id=%d get_pdata_int(id, 100) = %d (0x%x)", id, v, v);
		new v0 = get_pdata_int(id, 0, 0, 0);
		log_to_file(LOG, "  id=%d get_pdata_int(id, 0, 0, 0) = %d (0x%x)", id, v0, v0);
	}
	log_to_file(LOG, "run: done");
}
