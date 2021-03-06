/var/yog_round_number = 0

/world
	mob = /mob/new_player
	turf = /turf/space
	area = /area/space
	view = "15x15"
	cache_lifespan = 7

/world/New()
	map_ready = 1

#if (PRELOAD_RSC == 0)
	external_rsc_urls = file2list("config/external_rsc_urls.txt","\n")
	var/i=1
	while(i<=external_rsc_urls.len)
		if(external_rsc_urls[i])
			i++
		else
			external_rsc_urls.Cut(i,i+1)
#endif
	//logs
	var/date_string = time2text(world.realtime, "YYYY/MM-Month/DD-Day")
	href_logfile = file("data/logs/[date_string] hrefs.htm")
	diary = file("data/logs/[date_string].log")
	admindiary = file("data/logs/[date_string] Admin.log")
	diaryofmeanpeople = file("data/logs/[date_string] Attack.log")
	admindiary << "\n\nStarting up. [time2text(world.timeofday, "hh:mm.ss")]\n---------------------"
	diaryofmeanpeople << "\n\nStarting up. [time2text(world.timeofday, "hh:mm.ss")]\n---------------------"
	changelog_hash = md5('html/changelog.html')					//used for telling if the changelog has changed recently

	var/roundfile = file("data/roundcount.txt")
	yog_round_number = text2num(file2text(roundfile))
	if(yog_round_number == null || yog_round_number == "" || yog_round_number == 0)
		yog_round_number = 1
	else
		yog_round_number++
	fdel(roundfile)
	text2file(num2text(yog_round_number), roundfile)

	make_datum_references_lists()	//initialises global lists for referencing frequently used datums (so that we only ever do it once)

	load_configuration()
	load_mode()
	load_motd()
	load_admins()
	LoadBansjob()
	if(config.usewhitelist)
		load_whitelist()
	jobban_loadbanfile()
	appearance_loadbanfile()
	jobban_updatelegacybans()
	LoadBans()
	load_donators()
	investigate_reset()

	// Kn0ss0s: Uses regular expressions to filter unwanted words or phrases
	setup_pretty_filter()

	if(config && config.server_name != null && config.server_suffix && world.port > 0)
		config.server_name += " #[(world.port % 1000) / 100]"

	timezoneOffset = text2num(time2text(0,"hh")) * 36000

	if(config.sql_enabled)
		if(!setup_database_connection())
			world.log << "Your server failed to establish a connection with the database."
		else
			world.log << "Database connection established."


	data_core = new /datum/datacore()


	spawn(-1)
		master_controller.setup()

	process_teleport_locs()			//Sets up the wizard teleport locations
	SortAreas()						//Build the list of all existing areas and sort it alphabetically

	#ifdef MAP_NAME
	map_name = "[MAP_NAME]"
	#else
	map_name = "Unknown"
	#endif


	return


/world/Topic(T, addr, master, key)
	diary << "TOPIC: \"[T]\", from:[addr], master:[master], key:[key]"

	if (T == "ping")
		var/x = 1
		for (var/client/C in clients)
			x++
		return x

	else if(T == "players")
		var/n = 0
		for(var/mob/M in player_list)
			if(M.client)
				n++
		return n

	else if (T == "status")
		var/list/s = list()
		// Please add new status indexes under the old ones, for the server banner (until that gets reworked)
		s["version"] = game_version
		s["mode"] = master_mode
		s["respawn"] = config ? abandon_allowed : 0
		s["enter"] = enter_allowed
		s["vote"] = config.allow_vote_mode
		s["ai"] = config.allow_ai
		s["host"] = host ? host : null

		var/admins = 0
		for(var/client/C in clients)
			if(C.holder)
				if(C.holder.fakekey)
					continue	//so stealthmins aren't revealed by the hub
				admins++

		s["active_players"] = get_active_player_count()
		s["players"] = clients.len
		s["revision"] = revdata.revision
		s["revision_date"] = revdata.date
		s["admins"] = admins
		s["gamestate"] = 1
		if(ticker)
			s["gamestate"] = ticker.current_state
		s["map_name"] = map_name ? map_name : "Unknown"

		return list2params(s)
	else if (copytext(T,1,9) == "announce")
		var/input[] = params2list(T)
		if(global.comms_allowed)
			if(input["key"] != global.comms_key)
				return "Bad Key"
			else
#define CHAT_PULLR	64 //defined in preferences.dm, but not available here at compilation time
				for(var/client/C in clients)
					if(C.prefs && (C.prefs.chat_toggles & CHAT_PULLR))
						C << "<span class='announce'>PR: [input["announce"]]</span>"
#undef CHAT_PULLR

var/feedback_set = 0

/world/Reboot(var/reason, var/feedback_c, var/feedback_r, var/time)
	var/delay
	if(time)
		delay = time
	else
		delay = ticker.restart_timeout
	if(!feedback_set)
		feedback_set_details("[feedback_c]","[feedback_r]")
		feedback_set = 1
	if(ticker.delay_end)
		world << "<span class='boldannounce'>An admin has delayed the round end.</span>"
		return
	world << "<span class='boldannounce'>Rebooting World in [delay/10] [delay > 10 ? "seconds" : "second"]. [reason]</span>"
	sleep(delay)
	if(blackbox)
		blackbox.save_all_data_to_sql()
	if(ticker.delay_end)
		world << "<span class='boldannounce'>Reboot was cancelled by an admin.</span>"
		return
	log_game("<span class='boldannounce'>Rebooting World. [reason]</span>")
	kick_clients_in_lobby("<span class='boldannounce'>The round came to an end with you in the lobby.</span>", 1) //second parameter ensures only afk clients are kicked
	#ifdef dellogging
	var/log = file("data/logs/del.log")
	log << time2text(world.realtime)
	for(var/index in del_counter)
		var/count = del_counter[index]
		if(count > 10)
			log << "#[count]\t[index]"
#endif
	spawn(0)
		if(ticker && ticker.round_end_sound)
			world << sound(ticker.round_end_sound)
		else
			world << sound(pick('sound/AI/newroundsexy.ogg','sound/misc/apcdestroyed.ogg','sound/misc/bangindonk.ogg','sound/misc/leavingtg.ogg')) // random end sounds!! - LastyBatsy
	for(var/client/C in clients)
		if(config.server)	//if you set a server location in config.txt, it sends you there instead of trying to reconnect to the same world address. -- NeoFite
			C << link("byond://[config.server]")

	if(tickets_list)
		tickets_list.Cut()

	// Note: all clients automatically connect to the world after it restarts
	..(0)

/world/proc/manage_fps()
	var/count = player_list.len

	var/oldTC = config.Tickcomp
	var/oldFPS = world.fps

	if(count < 50)
		config.Tickcomp = 0
		world.fps = 22
	else if(count < 60)
		config.Tickcomp = 0
		world.fps = 21
	else if(count < 70)
		config.Tickcomp = 0
		world.fps = 20
	else if(count < 80)
		config.Tickcomp = 0
		world.fps = 19
	else if(count < 90)
		config.Tickcomp = 0
		world.fps = 18
	else
		config.Tickcomp = 1
		world.fps = 16

	if(world.fps != oldFPS || config.Tickcomp != oldTC)
		var/msg = "WORLD has modified world.fps to [world.fps] and config.Tickcomp to [config.Tickcomp] (player count reached [count])"
		log_admin(msg, 0)
		message_admins(msg, 0)

/world/proc/load_mode()
	var/list/Lines = file2list("data/mode.txt")
	if(Lines.len)
		if(Lines[1])
			master_mode = Lines[1]
			diary << "Saved mode is '[master_mode]'"

/world/proc/save_mode(the_mode)
	var/F = file("data/mode.txt")
	fdel(F)
	F << the_mode

/world/proc/load_motd()
	join_motd = file2text("config/motd.txt")

/world/proc/load_configuration()
	config = new /datum/configuration()
	config.load("config/config.txt")
	config.load("config/game_options.txt","game_options")
	config.loadsql("config/dbconfig.txt")
	// apply some settings from config..
	abandon_allowed = config.respawn

var/list/donators = list()

/world/proc/load_donators()
	var/ckey
	var/datum/preferences/P
	for(var/key in donators)
		ckey = ckey(key)
		P = preferences_datums[ckey]
		if(P)
			P.unlock_content &= 1
	donators = list()
	var/list/donatorskeys = list()
	if(config.donator_legacy_system)
		donatorskeys = file2list("config/donators.txt")
	else
		establish_db_connection()
		if(!dbcon.IsConnected())
			world.log << "Failed to connect to database in load_donators(). Reverting to legacy system."
			diary << "Failed to connect to database in load_donators(). Reverting to legacy system."
			config.donator_legacy_system = 1
			load_donators()
			return

		var/DBQuery/query = dbcon.NewQuery("SELECT ckey FROM [format_table_name("donors")] WHERE (expiration_time > Now()) AND (revoked IS NULL)")
		query.Execute()
		while(query.NextRow())
			ckey = query.item[1]
			if(ckey)
				donatorskeys |= ckey
	for(var/key in donatorskeys)
		ckey = ckey(key)
		donators += ckey
		P = preferences_datums[ckey]
		if(P)
			P.unlock_content |= 2

/world/proc/update_status()
	var/s = ""

	if (config && config.server_name)
		s += "<b>[config.server_name]</b> &#8212; "

	s += "<b>[station_name()]</b>";
	s += " ("
	s += "<a href=\"http://www.yogstation.net\">" //Change this to wherever you want the hub to link to.
//	s += "[game_version]"
	s += "www.yogstation.net"  //Replace this with something else. Or ever better, delete it and uncomment the game version.
	s += "</a>"
	s += ")"

	var/list/features = list()

	if(ticker)
		if(master_mode)
			features += master_mode
	else
		features += "<b>STARTING</b>"

	if (!enter_allowed)
		features += "closed"

	features += abandon_allowed ? "respawn" : "no respawn"

	if (config && config.allow_vote_mode)
		features += "vote"

	if (config && config.allow_ai)
		features += "AI allowed"

	var/n = 0
	for (var/mob/M in player_list)
		if (M.client)
			n++

	if (n > 1)
		features += "~[n] players"
	else if (n > 0)
		features += "~[n] player"

	/*
	is there a reason for this? the byond site shows 'hosted by X' when there is a proper host already.
	if (host)
		features += "hosted by <b>[host]</b>"
	*/

	if (!host && config && config.hostedby)
		features += "hosted by <b>[config.hostedby]</b>"

	if (features)
		s += ": [list2text(features, ", ")]"

	/* does this help? I do not know */
	if (src.status != s)
		src.status = s

#define FAILED_DB_CONNECTION_CUTOFF 5
var/failed_db_connections = 0

/proc/setup_database_connection()

	if(failed_db_connections >= FAILED_DB_CONNECTION_CUTOFF)	//If it failed to establish a connection more than 5 times in a row, don't bother attempting to connect anymore.
		return 0

	if(!dbcon)
		dbcon = new()

	var/user = sqlfdbklogin
	var/pass = sqlfdbkpass
	var/db = sqlfdbkdb
	var/address = sqladdress
	var/port = sqlport

	dbcon.Connect("dbi:mysql:[db]:[address]:[port]","[user]","[pass]")
	. = dbcon.IsConnected()
	if ( . )
		failed_db_connections = 0	//If this connection succeeded, reset the failed connections counter.
	else
		failed_db_connections++		//If it failed, increase the failed connections counter.
		if(config.sql_enabled)
			world.log << "SQL error: " + dbcon.ErrorMsg()

	return .

//This proc ensures that the connection to the feedback database (global variable dbcon) is established
/proc/establish_db_connection()
	if(failed_db_connections > FAILED_DB_CONNECTION_CUTOFF)
		return 0

	if(!dbcon || !dbcon.IsConnected())
		return setup_database_connection()
	else
		return 1

#undef FAILED_DB_CONNECTION_CUTOFF
