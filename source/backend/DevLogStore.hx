package states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import lime.app.Application;
import lime.system.Clipboard;
import openfl.events.KeyboardEvent;
import openfl.geom.Rectangle;
import openfl.system.Capabilities;
import openfl.system.System;
import backend.DevLogStore;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * DEV LOG - included in all builds (debug and release).
 * Tabs: SYSTEM, PERF, MODS, LOGS, FILES, CACHE, WATCH, CONSOLE
 * Number keys 1-8 or LEFT/RIGHT switch tabs. ESC exits.
 */
class DevLogState extends MusicBeatState
{
	static final TABS:Array<String> = ["SYSTEM", "PERF", "MODS", "LOGS", "FILES", "CACHE", "WATCH", "CONSOLE"];
	static final TEXT_EXTS:Array<String> = ["txt", "json", "lua", "hx", "hscript", "xml", "md", "ini", "log", "csv", "frag", "vert", "cfg", "yml"];

	var tab:Int = 0;
	var bodyTop:Float = 96;

	var tabBar:FlxText;
	var clockText:FlxText;
	var body:FlxText;
	var hint:FlxText;
	var inputText:FlxText;

	// perf
	var fpsGraph:FlxSprite;
	var ramGraph:FlxSprite;
	var fpsSamples:Array<Float> = [];
	var ramSamples:Array<Float> = [];
	var ramPeak:Float = 0;
	var sampleTimer:Float = 0;
	var frames:Int = 0;

	// timers / flags
	var clockTimer:Float = 0;
	var liveTimer:Float = 0;
	var flashTimer:Float = 0;
	var frozen:Bool = false;
	var hideUser:Bool = false;

	// files
	var fileDir:String = ".";
	var fileSel:Int = 0;
	var fileEntries:Array<String> = [];
	var preview:String = null;

	// console
	var consoleOut:Array<String> = [];
	var input:String = "";
	var history:Array<String> = [];
	var histIdx:Int = -1;
	var logFilter:String = "";

	// heads-up warning gate
	static var skipWarning:Bool = false; // resets when the game restarts
	var gateActive:Bool = false;
	var gateTimer:Float = 0;
	var gateGroup:flixel.group.FlxGroup;

	// saved keys (so typing in the console doesn't change volume)
	var oldMute:Array<FlxKey>;
	var oldVolUp:Array<FlxKey>;
	var oldVolDown:Array<FlxKey>;

	override function create()
	{
		FlxG.mouse.visible = true;

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		add(bg);

		var title = new FlxText(20, 8, FlxG.width - 40, "DEV LOG  |  Psych Engine " + MainMenuState.psychEngineVersion, 26);
		title.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.CYAN, LEFT);
		add(title);

		tabBar = new FlxText(20, 40, FlxG.width - 40, "", 18);
		tabBar.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT);
		add(tabBar);

		clockText = new FlxText(20, 64, FlxG.width - 40, "", 16);
		clockText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.YELLOW, LEFT);
		add(clockText);

		fpsGraph = new FlxSprite(20, 96).makeGraphic(300, 70, 0xFF000000);
		ramGraph = new FlxSprite(340, 96).makeGraphic(300, 70, 0xFF000000);
		add(fpsGraph);
		add(ramGraph);

		body = new FlxText(20, bodyTop, FlxG.width - 40, "", 15);
		body.setFormat(Paths.font("vcr.ttf"), 15, FlxColor.WHITE, LEFT);
		add(body);

		// opaque bars to hide scrolled text behind header/footer
		var topBar = new FlxSprite(0, 0).makeGraphic(FlxG.width, 90, 0xFF101018);
		var botBar = new FlxSprite(0, FlxG.height - 54).makeGraphic(FlxG.width, 54, 0xFF000000);
		// header elements sit above topBar, so re-add them after
		remove(title); remove(tabBar); remove(clockText);
		remove(fpsGraph); remove(ramGraph);
		add(topBar);
		add(title); add(tabBar); add(clockText);
		add(botBar);

		inputText = new FlxText(20, FlxG.height - 50, FlxG.width - 40, "", 18);
		inputText.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.LIME, LEFT);
		add(inputText);

		hint = new FlxText(20, FlxG.height - 24, FlxG.width - 40, "", 14);
		hint.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.GRAY, LEFT);
		add(hint);

		// graphs are drawn above the top bar but only visible on PERF
		add(fpsGraph);
		add(ramGraph);
		fpsGraph.y = 96;
		ramGraph.y = 96;

		oldMute = FlxG.sound.muteKeys;
		oldVolUp = FlxG.sound.volumeUpKeys;
		oldVolDown = FlxG.sound.volumeDownKeys;

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKey);

		#if sys
		loadDir(FileSystem.absolutePath("."));
		#end

		out("Dev console ready. Type 'help'.");
		setTab(0);
		updateClock();
		buildGate();
		super.create();
	}

	override function destroy()
	{
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKey);
		FlxG.sound.muteKeys = oldMute;
		FlxG.sound.volumeUpKeys = oldVolUp;
		FlxG.sound.volumeDownKeys = oldVolDown;
		super.destroy();
	}

	// ------------------------------------------------------------------ update

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (gateActive)
		{
			updateGate(elapsed);
			return;
		}

		// perf sampling (every 0.1s, averaged so single-frame spikes don't dominate)
		frames++;
		sampleTimer += elapsed;
		if (sampleTimer >= 0.1)
		{
			if (!frozen)
			{
				fpsSamples.push(frames / sampleTimer);
				if (fpsSamples.length > 300) fpsSamples.shift();
				var ram = System.totalMemory / 1048576;
				ramSamples.push(ram);
				if (ramSamples.length > 300) ramSamples.shift();
				if (ram > ramPeak) ramPeak = ram;
				if (tab == 1) drawGraphs();
			}
			sampleTimer = 0;
			frames = 0;
		}

		clockTimer += elapsed;
		if (clockTimer >= 0.5)
		{
			clockTimer = 0;
			updateClock();
		}

		// live tabs refresh
		liveTimer += elapsed;
		if (liveTimer >= 0.25 && !frozen && (tab == 1 || tab == 6))
		{
			liveTimer = 0;
			refresh(false);
		}

		if (flashTimer > 0)
		{
			flashTimer -= elapsed;
			if (flashTimer <= 0) setHint();
		}

		// ---- exit / back
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (tab == 7)
				setTab(0);
			else
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
			}
			return;
		}

		// ---- tab switching
		if (FlxG.keys.justPressed.RIGHT) setTab((tab + 1) % TABS.length);
		if (FlxG.keys.justPressed.LEFT) setTab((tab + TABS.length - 1) % TABS.length);

		if (tab == 7)
		{
			updateInputDisplay();
			scrollBody(elapsed, true);
			return;
		}

		var numKeys:Array<FlxKey> = [ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT];
		for (i in 0...TABS.length)
			if (FlxG.keys.anyJustPressed([numKeys[i]])) setTab(i);

		// ---- global hotkeys
		if (FlxG.keys.justPressed.R) refresh(true);
		if (FlxG.keys.justPressed.P)
		{
			frozen = !frozen;
			flash(frozen ? "Live updates FROZEN" : "Live updates resumed");
		}
		if (FlxG.keys.justPressed.H)
		{
			hideUser = !hideUser;
			refresh(false);
			flash(hideUser ? "Username hidden (safe to screenshot)" : "Username visible");
		}
		if (FlxG.keys.justPressed.G)
		{
			System.gc();
			flash("GC run. RAM now " + Math.round(System.totalMemory / 1048576) + " MB");
		}
		if (FlxG.keys.justPressed.C)
		{
			Clipboard.text = redact(FlxG.keys.pressed.SHIFT ? allText() : currentTabText());
			flash(FlxG.keys.pressed.SHIFT ? "Copied ALL tabs" : "Copied this tab");
		}
		if (FlxG.keys.justPressed.S) saveDump();

		if (tab == 4) updateFiles();
		else scrollBody(elapsed, false);
	}

	// ------------------------------------------------------------------ HEADS-UP GATE

	function buildGate()
	{
		if (skipWarning) return;
		gateActive = true;
		gateTimer = 0;
		gateGroup = new flixel.group.FlxGroup();

		var dim = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xEE000000);
		gateGroup.add(dim);

		var boxW:Int = Std.int(Math.min(FlxG.width - 80, 900));
		var boxH:Int = 440;
		var bx:Float = (FlxG.width - boxW) / 2;
		var by:Float = (FlxG.height - boxH) / 2;

		var border = new FlxSprite(bx - 3, by - 3).makeGraphic(boxW + 6, boxH + 6, 0xFFFFAA00);
		var box = new FlxSprite(bx, by).makeGraphic(boxW, boxH, 0xFF1A1A26);
		gateGroup.add(border);
		gateGroup.add(box);

		var title = new FlxText(bx + 30, by + 18, boxW - 60, "!  HEADS UP  -  DEVELOPER ONLY  !", 28);
		title.setFormat(Paths.font("vcr.ttf"), 28, 0xFFFFAA00, CENTER);
		gateGroup.add(title);

		var msg = "This screen shows personal info from THIS PC:\n\n"
			+ "  - Your PC username and computer name\n"
			+ "  - Your user folder and full file paths\n"
			+ "  - Hardware: CPU, GPU, RAM, OS\n"
			+ "  - Your local time and timezone\n"
			+ "  - Everything inside your game and mods folders\n\n"
			+ "Do NOT screenshot, record, stream, or copy/paste it anywhere public without hiding your username first.\n\n"
			+ "This screen is part of this build, so anyone running it can open it.";
		var body = new FlxText(bx + 30, by + 70, boxW - 60, msg, 17);
		body.setFormat(Paths.font("vcr.ttf"), 17, FlxColor.WHITE, LEFT);
		gateGroup.add(body);

		var prompt = new FlxText(bx + 30, by + boxH - 100, boxW - 60,
			"[ENTER] Continue\n"
			+ "[H] Continue with username HIDDEN\n"
			+ "[D] Continue and don't warn again this session\n"
			+ "[ESC] Go back", 16);
		prompt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.LIME, LEFT);
		gateGroup.add(prompt);

		add(gateGroup);
	}

	function updateGate(elapsed:Float)
	{
		// short delay so the ENTER you used to open this state doesn't instantly accept it
		gateTimer += elapsed;
		if (gateTimer < 0.35) return;

		if (FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new states.editors.MasterEditorMenu());
			return;
		}

		var go = false;
		if (FlxG.keys.justPressed.ENTER) go = true;
		if (FlxG.keys.justPressed.H)
		{
			hideUser = true;
			go = true;
		}
		if (FlxG.keys.justPressed.D)
		{
			skipWarning = true;
			go = true;
		}

		if (go)
		{
			gateActive = false;
			remove(gateGroup, true);
			gateGroup.destroy();
			gateGroup = null;
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
			updateClock();
			refresh(false);
		}
	}

	function scrollBody(elapsed:Float, bottomAnchored:Bool)
	{
		if (tab == 4) return;
		var visible:Float = FlxG.height - 54 - bodyTop;
		var minY:Float = Math.min(bodyTop, bodyTop + visible - body.height);
		var scroll:Float = FlxG.mouse.wheel * 45;
		if (FlxG.keys.pressed.UP && tab != 7) scroll += 500 * elapsed;
		if (FlxG.keys.pressed.DOWN && tab != 7) scroll -= 500 * elapsed;
		if (FlxG.keys.justPressed.PAGEUP) scroll += visible - 40;
		if (FlxG.keys.justPressed.PAGEDOWN) scroll -= visible - 40;
		if (FlxG.keys.justPressed.HOME) scroll = 99999;
		if (FlxG.keys.justPressed.END) scroll = -99999;
		if (scroll != 0) body.y = FlxMath.bound(body.y + scroll, minY, bodyTop);
	}

	// ------------------------------------------------------------------ tabs

	function setTab(t:Int)
	{
		tab = t;
		var tt = "";
		for (i in 0...TABS.length)
			tt += (i == tab ? "[" + (i + 1) + ":" + TABS[i] + "] " : " " + (i + 1) + ":" + TABS[i] + "  ");
		tabBar.text = tt;

		if (tab == 7)
		{
			FlxG.sound.muteKeys = [];
			FlxG.sound.volumeUpKeys = [];
			FlxG.sound.volumeDownKeys = [];
		}
		else
		{
			FlxG.sound.muteKeys = oldMute;
			FlxG.sound.volumeUpKeys = oldVolUp;
			FlxG.sound.volumeDownKeys = oldVolDown;
		}

		fpsGraph.visible = ramGraph.visible = (tab == 1);
		bodyTop = (tab == 1) ? 176 : 96;
		inputText.visible = (tab == 7);
		setHint();
		refresh(true);
		if (tab == 1) drawGraphs();
	}

	function setHint()
	{
		hint.text = switch (tab)
		{
			case 1: "P freeze | G run GC | C copy | S save | UP/DOWN scroll";
			case 4: "UP/DOWN select | ENTER open/preview | BACKSPACE up | O reveal in explorer | C copy";
			case 7: "ENTER run | UP/DOWN history | type 'help' | ESC back to SYSTEM";
			default: "1-8/LEFT/RIGHT tabs | C copy tab (SHIFT+C all) | S save to dev_logs | R refresh | H hide username | ESC exit";
		}
	}

	function flash(msg:String)
	{
		hint.text = msg;
		flashTimer = 2.2;
	}

	function refresh(resetScroll:Bool)
	{
		body.text = redact(currentTabText());
		if (resetScroll) body.y = bodyTop;
		if (tab == 4) body.y = bodyTop;
	}

	function currentTabText():String
		return tabText(tab);

	function tabText(t:Int):String
	{
		return switch (t)
		{
			case 0: sysText();
			case 1: perfText();
			case 2: modsText();
			case 3: logsText();
			case 4: filesText();
			case 5: cacheText();
			case 6: watchText();
			case 7: consoleOut.join("\n");
			default: "";
		}
	}

	function allText():String
	{
		var sb = new StringBuf();
		for (i in 0...TABS.length)
		{
			sb.add("################ " + TABS[i] + " ################\n");
			sb.add(tabText(i) + "\n\n");
		}
		return sb.toString();
	}

	function updateClock()
	{
		var d = Date.now();
		var off = -d.getTimezoneOffset() / 60;
		clockText.text = "Local: " + DateTools.format(d, "%Y-%m-%d  %H:%M:%S") + "  (UTC" + (off >= 0 ? "+" : "") + off + ")"
			+ "  |  Uptime: " + fmtTime(openfl.Lib.getTimer() / 1000)
			+ (frozen ? "  |  FROZEN" : "") + (hideUser ? "  |  USER HIDDEN" : "");
	}

	function fmtTime(sec:Float):String
	{
		var s = Std.int(sec);
		return Std.int(s / 3600) + "h " + Std.int((s % 3600) / 60) + "m " + (s % 60) + "s";
	}

	// ------------------------------------------------------------------ helpers

	function env(name:String, fallback:String = "N/A"):String
	{
		#if sys
		var v = Sys.getEnv(name);
		return v != null ? v : fallback;
		#else
		return fallback;
		#end
	}

	function userName():String
		return env("USERNAME", env("USER", ""));

	function redact(s:String):String
	{
		if (!hideUser) return s;
		var u = userName();
		if (u != null && u != "") s = StringTools.replace(s, u, "<user>");
		var pc = env("COMPUTERNAME", env("HOSTNAME", ""));
		if (pc != "") s = StringTools.replace(s, pc, "<pc>");
		return s;
	}

	function mb(bytes:Float):Float
		return Math.round(bytes / 1048576 * 100) / 100;

	function cmpStr(a:String, b:String):Int
		return Reflect.compare(a.toLowerCase(), b.toLowerCase());

	// ------------------------------------------------------------------ SYSTEM

	function sysText():String
	{
		var sb = new StringBuf();
		function line(s:String) sb.add(s + "\n");

		line("=== USER / MACHINE ===");
		#if sys
		line("Username:    " + userName());
		line("PC Name:     " + env("COMPUTERNAME", env("HOSTNAME")));
		line("OS:          " + Sys.systemName() + " (" + Capabilities.os + ")");
		line("User folder: " + env("USERPROFILE", env("HOME")));
		line("CPU cores:   " + env("NUMBER_OF_PROCESSORS"));
		line("CPU name:    " + env("PROCESSOR_IDENTIFIER"));
		line("CPU arch:    " + Capabilities.cpuArchitecture);
		line("Executable:  " + Sys.programPath());
		line("Working dir: " + Sys.getCwd());
		line("Launch args: " + Sys.args().join(" "));
		#else
		line("(non-sys target, limited info)");
		#end
		var d = Date.now();
		line("Timezone:    UTC" + (-d.getTimezoneOffset() / 60 >= 0 ? "+" : "") + (-d.getTimezoneOffset() / 60));

		line("");
		line("=== DISPLAY / GPU ===");
		line("Screen:      " + Std.int(Capabilities.screenResolutionX) + "x" + Std.int(Capabilities.screenResolutionY) + " @ DPI " + Capabilities.screenDPI);
		line("Stage:       " + FlxG.stage.stageWidth + "x" + FlxG.stage.stageHeight);
		line("Game size:   " + FlxG.width + "x" + FlxG.height);
		line("Fullscreen:  " + FlxG.fullscreen);
		line("Framerate:   " + FlxG.drawFramerate + " draw / " + FlxG.updateFramerate + " update");
		try
		{
			line("Driver:      " + FlxG.stage.context3D.driverInfo);
		}
		catch (e:Dynamic)
			line("Driver:      unavailable");
		try
		{
			line("GL renderer: " + lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.RENDERER));
			line("GL vendor:   " + lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.VENDOR));
			line("GL version:  " + lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.VERSION));
		}
		catch (e:Dynamic)
			line("GL info:     unavailable");

		line("");
		line("=== AUDIO / INPUT ===");
		line("Volume:      " + FlxG.sound.volume + (FlxG.sound.muted ? " (MUTED)" : ""));
		line("Music:       " + (FlxG.sound.music != null ? "playing=" + FlxG.sound.music.playing + " time=" + Math.round(FlxG.sound.music.time) + "ms len=" + Math.round(FlxG.sound.music.length) + "ms" : "none"));
		line("Gamepads:    " + FlxG.gamepads.numActiveGamepads);
		for (i in 0...FlxG.gamepads.numActiveGamepads)
		{
			var gp = FlxG.gamepads.getByID(i);
			if (gp != null) line("  [" + i + "] " + gp.name + " (" + gp.model + ")");
		}

		line("");
		line("=== MEMORY ===");
		line("Game RAM:    " + mb(System.totalMemory) + " MB (peak this session " + Math.round(ramPeak) + " MB)");

		line("");
		line("=== ENGINE ===");
		line("Psych Engine: " + MainMenuState.psychEngineVersion);
		line("App version:  " + Application.current.meta.get('version'));
		line("Flixel:       " + FlxG.VERSION);
		line("Current state: " + Type.getClassName(Type.getClass(FlxG.state)));

		var defs:Array<String> = [];
		#if debug defs.push("debug"); #end
		#if MODS_ALLOWED defs.push("MODS_ALLOWED"); #end
		#if LUA_ALLOWED defs.push("LUA_ALLOWED"); #end
		#if HSCRIPT_ALLOWED defs.push("HSCRIPT_ALLOWED"); #end
		#if VIDEOS_ALLOWED defs.push("VIDEOS_ALLOWED"); #end
		#if ACHIEVEMENTS_ALLOWED defs.push("ACHIEVEMENTS_ALLOWED"); #end
		#if DISCORD_ALLOWED defs.push("DISCORD_ALLOWED"); #end
		#if cpp defs.push("cpp"); #end
		#if hl defs.push("hl"); #end
		line("Build flags:  " + defs.join(", "));

		#if sys
		line("");
		line("=== GAME DIRECTORY (2 levels) ===");
		var cwd = Sys.getCwd();
		line("Path: " + cwd);
		treeDir(sb, cwd, 0, 2);
		#end
		return sb.toString();
	}

	#if sys
	function treeDir(sb:StringBuf, path:String, depth:Int, maxDepth:Int)
	{
		var indent = StringTools.rpad("", " ", depth * 2 + 2);
		try
		{
			var entries = FileSystem.readDirectory(path);
			entries.sort(cmpStr);
			var shown = 0;
			for (e in entries)
			{
				if (shown++ >= 40)
				{
					sb.add(indent + "... (" + (entries.length - 40) + " more)\n");
					break;
				}
				var full = haxe.io.Path.addTrailingSlash(path) + e;
				if (FileSystem.isDirectory(full))
				{
					sb.add(indent + "[" + e + "]\n");
					if (depth < maxDepth - 1) treeDir(sb, full, depth + 1, maxDepth);
				}
				else
					sb.add(indent + e + "  (" + Math.round(FileSystem.stat(full).size / 1024) + " KB)\n");
			}
		}
		catch (e:Dynamic)
			sb.add(indent + "(cannot read: " + e + ")\n");
	}

	function countFiles(path:String, depth:Int = 0):Int
	{
		if (depth > 6) return 0;
		var n = 0;
		try
		{
			for (e in FileSystem.readDirectory(path))
			{
				var full = haxe.io.Path.join([path, e]);
				if (FileSystem.isDirectory(full)) n += countFiles(full, depth + 1);
				else n++;
			}
		}
		catch (e:Dynamic) {}
		return n;
	}
	#end

	// ------------------------------------------------------------------ PERF

	function perfText():String
	{
		var sb = new StringBuf();
		function line(s:String) sb.add(s + "\n");

		var n = fpsSamples.length;
		var avg:Float = 0, mn:Float = 99999, mx:Float = 0;
		for (s in fpsSamples)
		{
			avg += s;
			if (s < mn) mn = s;
			if (s > mx) mx = s;
		}
		if (n > 0) avg /= n; else mn = 0;
		var sorted = fpsSamples.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var low1 = n > 0 ? sorted[Std.int(n * 0.01)] : 0;
		var cur = n > 0 ? fpsSamples[n - 1] : 0;

		line("=== FRAMERATE (left graph: FPS, right graph: RAM MB) ===");
		line("Now: " + Math.round(cur) + " | Avg: " + Math.round(avg) + " | Min: " + Math.round(mn) + " | Max: " + Math.round(mx) + " | 1% low: " + Math.round(low1));
		line("Frame time: " + (cur > 0 ? Math.round(1000 / cur * 100) / 100 : 0) + " ms (target " + Math.round(1000 / FlxG.drawFramerate * 100) / 100 + " ms)");
		line("");
		line("=== MEMORY ===");
		line("RAM now:  " + mb(System.totalMemory) + " MB");
		line("RAM peak: " + Math.round(ramPeak) + " MB");
		if (ramSamples.length > 20)
		{
			var drift = ramSamples[ramSamples.length - 1] - ramSamples[0];
			line("Trend over graph window: " + (drift >= 0 ? "+" : "") + Math.round(drift * 10) / 10 + " MB" + (drift > 50 ? "  <-- possible leak, try 'clearcache'" : ""));
		}
		line("");
		line("=== SCENE ===");
		line("State members:  " + (FlxG.state != null ? FlxG.state.members.length : 0));
		line("Cameras:        " + FlxG.cameras.list.length);
		line("Sounds loaded:  " + FlxG.sound.list.length);
		line("Substate open:  " + (FlxG.state != null && FlxG.state.subState != null));
		line("timeScale:      " + FlxG.timeScale);
		return sb.toString();
	}

	function drawGraphs()
	{
		drawGraph(fpsGraph, fpsSamples, FlxG.drawFramerate * 1.2, true);
		var peak = Math.max(ramPeak * 1.1, 100);
		drawGraph(ramGraph, ramSamples, peak, false);
	}

	function drawGraph(spr:FlxSprite, samples:Array<Float>, maxV:Float, lowIsBad:Bool)
	{
		var bmp = spr.pixels;
		bmp.lock();
		bmp.fillRect(bmp.rect, 0xFF000000);
		var offset = Std.int(Math.max(0, samples.length - 300));
		for (i in 0...samples.length)
		{
			var v = samples[i];
			var h = Std.int(FlxMath.bound(v / maxV, 0, 1) * 70);
			var col:Int = 0xFF00AAFF;
			if (lowIsBad)
			{
				var t = FlxG.drawFramerate;
				col = v >= t * 0.9 ? 0xFF00FF00 : (v >= t * 0.6 ? 0xFFFFFF00 : 0xFFFF0000);
			}
			bmp.fillRect(new Rectangle(i, 70 - h, 1, h), col);
		}
		bmp.unlock();
		spr.dirty = true;
	}

	// ------------------------------------------------------------------ MODS

	function modsText():String
	{
		var sb = new StringBuf();
		function line(s:String) sb.add(s + "\n");
		line("=== MODS ===");
		#if MODS_ALLOWED
		try
		{
			var list = Mods.parseList();
			line("Current mod: " + (Mods.currentModDirectory == "" ? "(none)" : Mods.currentModDirectory));
			var globals = Mods.getGlobalMods();
			line("");
			line("Enabled (" + list.enabled.length + "):");
			for (m in list.enabled)
			{
				var info = "";
				#if sys
				var p = "mods/" + m;
				info = "  " + countFiles(p) + " files"
					+ (FileSystem.exists(p + "/pack.json") ? "  pack.json" : "  (NO pack.json)")
					+ (FileSystem.exists(p + "/scripts") ? "  scripts/" : "")
					+ (FileSystem.exists(p + "/custom_events") ? "  events/" : "")
					+ (FileSystem.exists(p + "/stages") ? "  stages/" : "");
				#end
				line("  [ON]  " + m + (globals.contains(m) ? " (global)" : "") + info);
			}
			line("");
			line("Disabled (" + list.disabled.length + "):");
			for (m in list.disabled) line("  [OFF] " + m);
		}
		catch (e:Dynamic)
			line("Could not read mods (API names may differ in your build): " + e);
		#else
		line("(MODS_ALLOWED is off in this build)");
		#end
		return sb.toString();
	}

	// ------------------------------------------------------------------ LOGS

	function logsText():String
	{
		var sb = new StringBuf();
		function section(title:String, arr:Array<String>, last:Int)
		{
			sb.add("=== " + title + " (" + arr.length + ") ===\n");
			var shown = 0;
			var start = Std.int(Math.max(0, arr.length - last));
			for (i in start...arr.length)
			{
				if (logFilter != "" && arr[i].toLowerCase().indexOf(logFilter.toLowerCase()) < 0) continue;
				sb.add("  " + arr[i] + "\n");
				shown++;
			}
			if (shown == 0) sb.add("  none\n");
			sb.add("\n");
		}
		if (logFilter != "") sb.add("(filter: '" + logFilter + "'  -  clear with: filter)\n\n");
		section("UNCAUGHT ERRORS", DevLogStore.errors, 50);
		section("LUA ERRORS / DEBUGPRINT", DevLogStore.luaErrors, 100);
		section("EVENTS TIMELINE", DevLogStore.events, 100);
		section("TRACE OUTPUT (last 150)", DevLogStore.traces, 150);
		return sb.toString();
	}

	// ------------------------------------------------------------------ FILES

	#if sys
	function loadDir(p:String)
	{
		fileDir = p;
		fileSel = 0;
		preview = null;
		try
		{
			var all = FileSystem.readDirectory(p);
			var dirs = all.filter(e -> FileSystem.isDirectory(haxe.io.Path.join([p, e])));
			var files = all.filter(e -> !FileSystem.isDirectory(haxe.io.Path.join([p, e])));
			dirs.sort(cmpStr);
			files.sort(cmpStr);
			fileEntries = dirs.map(d -> d + "/").concat(files);
		}
		catch (e:Dynamic)
			fileEntries = [];
	}

	function readPreview(full:String):String
	{
		var ext = haxe.io.Path.extension(full).toLowerCase();
		var size = FileSystem.stat(full).size;
		if (TEXT_EXTS.indexOf(ext) < 0)
			return "Binary / unknown file type: ." + ext + "  (" + Math.round(size / 1024) + " KB)";
		if (size > 2 * 1048576) return "File too large to preview (" + Math.round(size / 1024) + " KB)";
		var lines = File.getContent(full).split("\n");
		var sb = new StringBuf();
		for (i in 0...Std.int(Math.min(lines.length, 120)))
			sb.add(StringTools.lpad(Std.string(i + 1), " ", 4) + " | " + StringTools.rtrim(lines[i]) + "\n");
		if (lines.length > 120) sb.add("... (" + (lines.length - 120) + " more lines)\n");
		return sb.toString();
	}

	function updateFiles()
	{
		var changed = false;
		if (preview == null)
		{
			if (FlxG.keys.justPressed.UP) { fileSel = Std.int(Math.max(0, fileSel - 1)); changed = true; }
			if (FlxG.keys.justPressed.DOWN) { fileSel = Std.int(Math.min(fileEntries.length - 1, fileSel + 1)); changed = true; }
			if (FlxG.mouse.wheel != 0)
			{
				fileSel = Std.int(FlxMath.bound(fileSel - FlxG.mouse.wheel * 3, 0, Math.max(0, fileEntries.length - 1)));
				changed = true;
			}
		}
		else
			scrollPreview();

		if (FlxG.keys.justPressed.ENTER && preview == null && fileEntries.length > 0)
		{
			var e = fileEntries[fileSel];
			if (StringTools.endsWith(e, "/"))
				loadDir(haxe.io.Path.join([fileDir, e.substr(0, e.length - 1)]));
			else
				preview = readPreview(haxe.io.Path.join([fileDir, e]));
			changed = true;
		}
		if (FlxG.keys.justPressed.BACKSPACE)
		{
			if (preview != null) preview = null;
			else
			{
				var parent = haxe.io.Path.directory(haxe.io.Path.removeTrailingSlashes(fileDir));
				if (parent != "") loadDir(parent);
			}
			changed = true;
		}
		if (FlxG.keys.justPressed.O)
		{
			openPath(fileDir);
			flash("Opened in file explorer");
		}
		if (changed) refresh(true);
	}

	function scrollPreview()
	{
		var visible:Float = FlxG.height - 54 - bodyTop;
		var minY:Float = Math.min(bodyTop, bodyTop + visible - body.height);
		var s:Float = FlxG.mouse.wheel * 45;
		if (FlxG.keys.pressed.UP) s += 12;
		if (FlxG.keys.pressed.DOWN) s -= 12;
		if (s != 0) body.y = FlxMath.bound(body.y + s, minY, bodyTop);
	}

	function openPath(p:String)
	{
		var os = Sys.systemName();
		try
		{
			if (os == "Windows") Sys.command("explorer", [StringTools.replace(p, "/", "\\")]);
			else if (os == "Mac") Sys.command("open", [p]);
			else Sys.command("xdg-open", [p]);
		}
		catch (e:Dynamic) {}
	}

	function grepDir(dir:String, needle:String, hits:Array<String>, depth:Int)
	{
		if (depth > 8 || hits.length >= 60) return;
		try
		{
			for (e in FileSystem.readDirectory(dir))
			{
				var full = haxe.io.Path.join([dir, e]);
				if (FileSystem.isDirectory(full)) grepDir(full, needle, hits, depth + 1);
				else if (TEXT_EXTS.indexOf(haxe.io.Path.extension(e).toLowerCase()) >= 0 && FileSystem.stat(full).size < 1048576)
				{
					var ls = File.getContent(full).split("\n");
					for (i in 0...ls.length)
						if (ls[i].toLowerCase().indexOf(needle.toLowerCase()) >= 0 && hits.length < 60)
							hits.push(full + ":" + (i + 1) + ": " + StringTools.trim(ls[i]));
				}
			}
		}
		catch (e:Dynamic) {}
	}
	#end

	function filesText():String
	{
		#if sys
		var sb = new StringBuf();
		sb.add("Dir: " + fileDir + "\n");
		if (preview != null)
		{
			sb.add("Previewing: " + fileEntries[fileSel] + "   (BACKSPACE to close)\n");
			sb.add("------------------------------------------------\n");
			sb.add(preview);
			return sb.toString();
		}
		sb.add(fileEntries.length + " entries\n");
		sb.add("------------------------------------------------\n");
		var win = 26;
		var start = Std.int(Math.max(0, Math.min(fileSel - Std.int(win / 2), fileEntries.length - win)));
		var end = Std.int(Math.min(fileEntries.length, start + win));
		if (start > 0) sb.add("   ...\n");
		for (i in start...end)
		{
			var e = fileEntries[i];
			var size = "";
			if (!StringTools.endsWith(e, "/"))
			{
				try size = "  (" + Math.round(FileSystem.stat(haxe.io.Path.join([fileDir, e])).size / 1024) + " KB)" catch (x:Dynamic) {}
			}
			sb.add((i == fileSel ? " > " : "   ") + e + size + "\n");
		}
		if (end < fileEntries.length) sb.add("   ... " + (fileEntries.length - end) + " more\n");
		return sb.toString();
		#else
		return "File browser needs a sys target.";
		#end
	}

	// ------------------------------------------------------------------ CACHE

	function cacheText():String
	{
		var sb = new StringBuf();
		try
		{
			var items:Array<{k:String, b:Float}> = [];
			var total:Float = 0;
			for (k => g in Paths.currentTrackedAssets)
			{
				var b = g.width * g.height * 4.0;
				total += b;
				items.push({k: k, b: b});
			}
			items.sort((a, b) -> a.b < b.b ? 1 : (a.b > b.b ? -1 : 0));
			sb.add("=== TRACKED GRAPHICS: " + items.length + "   est. VRAM: " + mb(total) + " MB ===\n");
			sb.add("(sorted biggest first, top 70)\n");
			for (i in 0...Std.int(Math.min(items.length, 70)))
				sb.add("  " + StringTools.lpad(Std.string(mb(items[i].b)), " ", 8) + " MB  " + items[i].k + "\n");

			var snd:Array<String> = [];
			for (k in Paths.currentTrackedSounds.keys()) snd.push(k);
			snd.sort(cmpStr);
			sb.add("\n=== TRACKED SOUNDS: " + snd.length + " ===\n");
			for (s in snd) sb.add("  " + s + "\n");
			sb.add("\nTip: console 'clearcache' frees unused assets.\n");
		}
		catch (e:Dynamic)
			sb.add("Could not read Paths cache (field names differ in your build): " + e);
		return sb.toString();
	}

	// ------------------------------------------------------------------ WATCH

	function watchText():String
	{
		var sb = new StringBuf();
		sb.add("=== LIVE WATCHES ===\n");
		sb.add("Add your own from any code:\n  DevLogStore.watch(\"name\", () -> someValue);\n\n");
		var keys:Array<String> = [];
		for (k in DevLogStore.watches.keys()) keys.push(k);
		keys.sort(cmpStr);
		for (k in keys)
		{
			var v:String;
			try v = Std.string(DevLogStore.watches.get(k)()) catch (e:Dynamic) v = "<error: " + e + ">";
			sb.add("  " + StringTools.rpad(k, " ", 22) + " = " + v + "\n");
		}
		return sb.toString();
	}

	// ------------------------------------------------------------------ CONSOLE

	function out(s:String)
	{
		for (l in s.split("\n")) consoleOut.push(l);
		while (consoleOut.length > 300) consoleOut.shift();
	}

	function updateInputDisplay()
	{
		var cursor = (Std.int(openfl.Lib.getTimer() / 500) % 2 == 0) ? "_" : " ";
		inputText.text = "> " + input + cursor;
	}

	function onKey(e:KeyboardEvent)
	{
		if (tab != 7) return;
		switch (e.keyCode)
		{
			case 13:
				var cmd = StringTools.trim(input);
				if (cmd != "")
				{
					history.push(cmd);
					histIdx = history.length;
					out("> " + cmd);
					try runCommand(cmd) catch (ex:Dynamic) out("ERROR: " + ex);
				}
				input = "";
				refresh(false);
				body.y = Math.min(bodyTop, bodyTop + (FlxG.height - 54 - bodyTop) - body.height);
			case 8:
				if (input.length > 0) input = input.substr(0, input.length - 1);
			case 38:
				if (history.length > 0)
				{
					histIdx = Std.int(Math.max(0, histIdx - 1));
					input = history[histIdx];
				}
			case 40:
				if (history.length > 0)
				{
					histIdx = Std.int(Math.min(history.length, histIdx + 1));
					input = histIdx >= history.length ? "" : history[histIdx];
				}
			default:
				if (e.charCode >= 32 && e.charCode < 127) input += String.fromCharCode(e.charCode);
		}
	}

	function runCommand(line:String)
	{
		var parts = line.split(" ");
		var cmd = parts.shift().toLowerCase();
		var arg = parts.join(" ");

		switch (cmd)
		{
			case "help":
				out("help               this list");
				out("clear              clear console");
				out("fps <n>            set framerate");
				out("timescale <x>      set FlxG.timeScale (0.1 - 5)");
				out("volume <0-1>       set master volume");
				out("state <Name>       switch to states.<Name> (e.g. state TitleState)");
				out("reset              reset current state");
				out("gc                 run garbage collector");
				out("clearcache         free unused assets");
				out("prefs              list all ClientPrefs.data values");
				out("pref <name> <val>  change a pref live (not saved to disk)");
				out("env <NAME>         read an environment variable");
				out("ls [path]          list a folder");
				out("open <path>        open folder in file explorer");
				out("grep <text>        search text in mods/ (lua, json, hx, xml...)");
				out("filter <text>      filter LOGS tab (empty = clear)");
				out("event <text>       add a marker to the events timeline");
				out("dump               save all tabs to dev_logs/");
				out("hide               toggle username redaction");
			case "clear":
				consoleOut = [];
			case "fps":
				var n = Std.parseInt(arg);
				if (n == null || n < 10 || n > 1000) { out("usage: fps <10-1000>"); return; }
				ClientPrefs.data.framerate = n;
				FlxG.drawFramerate = FlxG.updateFramerate = n;
				out("framerate = " + n);
			case "timescale":
				var f = Std.parseFloat(arg);
				if (Math.isNaN(f) || f < 0.1 || f > 5) { out("usage: timescale <0.1-5>"); return; }
				FlxG.timeScale = f;
				out("timeScale = " + f);
			case "volume":
				var f = Std.parseFloat(arg);
				if (Math.isNaN(f)) { out("usage: volume <0-1>"); return; }
				FlxG.sound.volume = FlxMath.bound(f, 0, 1);
				out("volume = " + FlxG.sound.volume);
			case "state":
				var cls = Type.resolveClass("states." + arg);
				if (cls == null) cls = Type.resolveClass(arg);
				if (cls == null) { out("class not found: " + arg); return; }
				MusicBeatState.switchState(cast Type.createInstance(cls, []));
			case "reset":
				MusicBeatState.resetState();
			case "gc":
				System.gc();
				out("GC done. RAM " + mb(System.totalMemory) + " MB");
			case "clearcache":
				Paths.clearUnusedMemory();
				Paths.clearStoredMemory();
				System.gc();
				out("Cache cleared. RAM " + mb(System.totalMemory) + " MB");
			case "prefs":
				var fields = Reflect.fields(ClientPrefs.data);
				fields.sort(cmpStr);
				for (f in fields) out("  " + f + " = " + Std.string(Reflect.field(ClientPrefs.data, f)));
			case "pref":
				var p = arg.split(" ");
				if (p.length < 2) { out("usage: pref <name> <value>"); return; }
				var name = p[0];
				var raw = p[1];
				if (!Reflect.hasField(ClientPrefs.data, name)) { out("no such pref: " + name); return; }
				var val:Dynamic = raw;
				if (raw == "true") val = true;
				else if (raw == "false") val = false;
				else if (!Math.isNaN(Std.parseFloat(raw))) val = (raw.indexOf(".") >= 0) ? Std.parseFloat(raw) : Std.parseInt(raw);
				Reflect.setField(ClientPrefs.data, name, val);
				out(name + " = " + Std.string(val));
			case "env":
				out(arg + " = " + env(arg));
			case "event":
				DevLogStore.event(arg);
				out("event logged");
			case "filter":
				logFilter = arg;
				out(arg == "" ? "filter cleared" : "LOGS filter = '" + arg + "'");
			case "hide":
				hideUser = !hideUser;
				out("username redaction " + (hideUser ? "ON" : "OFF"));
			case "dump":
				saveDump();
			#if sys
			case "ls":
				var p = arg == "" ? fileDir : arg;
				if (!FileSystem.exists(p)) { out("not found: " + p); return; }
				var es = FileSystem.readDirectory(p);
				es.sort(cmpStr);
				for (e in es) out("  " + (FileSystem.isDirectory(haxe.io.Path.join([p, e])) ? "[" + e + "]" : e));
			case "open":
				openPath(arg == "" ? fileDir : arg);
				out("opened");
			case "grep":
				if (arg == "") { out("usage: grep <text>"); return; }
				var hits:Array<String> = [];
				grepDir("mods", arg, hits, 0);
				if (hits.length == 0) out("no matches in mods/");
				for (h in hits) out(h);
				if (hits.length >= 60) out("... stopped at 60 matches");
			#end
			default:
				out("unknown command: " + cmd + "  (try 'help')");
		}
	}

	// ------------------------------------------------------------------ SAVE

	function saveDump()
	{
		#if sys
		try
		{
			if (!FileSystem.exists("dev_logs")) FileSystem.createDirectory("dev_logs");
			var path = "dev_logs/devlog_" + DateTools.format(Date.now(), "%Y%m%d_%H%M%S") + ".txt";
			File.saveContent(path, redact(allText()));
			flash("Saved: " + path);
			out("saved " + path);
		}
		catch (e:Dynamic)
			flash("Save failed: " + e);
		#end
	}
}
