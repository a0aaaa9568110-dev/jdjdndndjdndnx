package substates;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.FlxBasic;
import flixel.util.FlxStringUtil;
import flixel.input.keyboard.FlxKey;
import haxe.Json;
import openfl.display.BlendMode;
import openfl.filters.BitmapFilter;
import openfl.filters.BlurFilter;

import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;

class PauseSubState extends MusicBeatSubstate
{
	var grpMenuShit:FlxTypedGroup<Alphabet>;

	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = [];
	static final DEFAULT_ITEMS:Array<String> = ['Resume', 'Restart Song', 'Change Difficulty', 'Toggle Botplay', 'Options', 'Exit to menu'];

	// Valid keys, used to warn about typos in pauseMenu.json
	static final DIRECTIONS:Array<String> = ['left', 'right', 'top', 'bottom'];
	static final KEYS_ROOT:Array<String> = ['font', 'hotReloadKey', 'menuItems', 'labels', 'animations', 'background', 'menu', 'cursor', 'sounds', 'music', 'infoTexts', 'extraTexts'];
	static final KEYS_ANIM:Array<String> = ['slideIn', 'slideOut', 'slideOutTime'];
	static final KEYS_BG:Array<String> = ['color', 'tint', 'alpha', 'fadeTime', 'image', 'scaleMode', 'blend', 'blur'];
	static final KEYS_MENU:Array<String> = ['x', 'y', 'offsetX', 'align', 'distanceX', 'distanceY', 'inactiveAlpha', 'color', 'selectedColor', 'selectedScale', 'slideIn', 'slideFrom', 'slideTo', 'slideStagger'];
	static final KEYS_CURSOR:Array<String> = ['visible', 'text', 'image', 'size', 'scale', 'color', 'offsetX', 'offsetY'];
	static final KEYS_SOUNDS:Array<String> = ['scroll', 'scrollVolume', 'confirm', 'confirmVolume'];
	static final KEYS_MUSIC:Array<String> = ['track', 'maxVolume', 'fadeSpeed'];
	static final KEYS_INFOTEXTS:Array<String> = ['song', 'difficulty', 'blueballed', 'practice', 'charting'];
	static final KEYS_TEXT:Array<String> = ['visible', 'text', 'size', 'color', 'align', 'y', 'offsetX', 'offsetY', 'slideIn', 'slideFrom', 'slideTo', 'delay', 'showWhen'];
	static final KEYS_ITEM:Array<String> = ['id', 'label', 'action', 'showWhen', 'state', 'url', 'sound', 'callback', 'args', 'closeAfter', 'menuMusic'];

	// Loaded from data/pauseMenu.json (or data/<song>/pauseMenu.json). null = use hardcoded defaults.
	var menuData:Dynamic = null;
	var itemDefs:Map<String, Dynamic> = new Map();
	var fontName:String = 'vcr.ttf';
	var inactiveAlpha:Float = 0.6;
	var menuColor:FlxColor = FlxColor.WHITE;
	var selectedColor:FlxColor = FlxColor.WHITE;
	var selectedScale:Float = 1;
	var maxMusicVolume:Float = 0.5;
	var musicFadeSpeed:Float = 0.01;
	var reloadKey:FlxKey = FlxKey.NONE;

	var bg:FlxSprite;
	var cursor:FlxSprite;
	var infoTexts:Array<FlxText> = [];
	var infoTextTo:Array<String> = [];
	var uiObjects:Array<FlxBasic> = [];
	var closing:Bool = false;
	var blurApplied:Bool = false;

	var difficultyChoices = [];
	var curSelected:Int = 0;

	var pauseMusic:FlxSound;
	var practiceText:FlxText;
	var skipTimeText:FlxText;
	var skipTimeTracker:Alphabet;
	var curTime:Float = Math.max(0, Conductor.songPosition);

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	public static var songName:String = null;

	override function create()
	{
		loadConfig();
		setupMusic();
		buildMenuList();
		buildUI();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		super.create();
	}

	// ---------------------------------------------------------------------
	//  Setup
	// ---------------------------------------------------------------------

	function loadConfig():Void
	{
		loadMenuData();
		validateConfig();

		fontName = cfgString('font', 'vcr.ttf');
		inactiveAlpha = cfgFloat('menu.inactiveAlpha', 0.6);
		menuColor = cfgColor('menu.color', FlxColor.WHITE);
		selectedColor = cfgColor('menu.selectedColor', FlxColor.WHITE);
		selectedScale = cfgFloat('menu.selectedScale', 1);
		maxMusicVolume = cfgFloat('music.maxVolume', 0.5);
		musicFadeSpeed = cfgFloat('music.fadeSpeed', 0.01);
		reloadKey = FlxKey.fromString(cfgString('hotReloadKey', 'F6').toUpperCase());
	}

	function setupMusic():Void
	{
		pauseMusic = new FlxSound();
		try
		{
			var pauseSong:String = getPauseSong();
			if(pauseSong != null) pauseMusic.loadEmbedded(Paths.music(pauseSong), true, true);
		}
		catch(e:Dynamic) {}
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));

		FlxG.sound.list.add(pauseMusic);
	}

	function buildMenuList():Void
	{
		itemDefs = new Map();
		menuItemsOG = getBaseMenuItems();

		if(Difficulty.list.length < 2) menuItemsOG.remove('Change Difficulty'); //No need to change difficulty if there is only one!
		if(PlayState.chartingMode)
		{
			menuItemsOG.insert(2, 'Leave Charting Mode');
			var num:Int = 0;
			if(!PlayState.instance.startingSong)
			{
				num = 1;
				menuItemsOG.insert(3, 'Skip Time');
			}
			menuItemsOG.insert(3 + num, 'End Song');
			menuItemsOG.insert(4 + num, 'Toggle Practice Mode');
			if(!menuItemsOG.contains('Toggle Botplay')) menuItemsOG.insert(5 + num, 'Toggle Botplay'); // already in the list? don't duplicate
		} else if(PlayState.instance.practiceMode && !PlayState.instance.startingSong)
			menuItemsOG.insert(3, 'Skip Time');
		menuItems = menuItemsOG;

		difficultyChoices = [];
		for (i in 0...Difficulty.list.length) {
			var diff:String = Difficulty.getString(i);
			difficultyChoices.push(diff);
		}
		difficultyChoices.push('BACK');
	}

	function buildUI():Void
	{
		closing = false;
		curSelected = 0;
		infoTexts = [];
		infoTextTo = [];

		createBackground();

		// Info texts (all configurable under "infoTexts" / "extraTexts" in the JSON)
		createInfoText(cfg('infoTexts.song', null), PlayState.SONG.song, 20, 32, 0.3, true);
		createInfoText(cfg('infoTexts.difficulty', null), Difficulty.getString().toUpperCase(), 52, 32, 0.45, true);
		createInfoText(cfg('infoTexts.blueballed', null), Language.getPhrase("blueballed", "Blueballed: {1}", [PlayState.deathCounter]), 84, 32, 0.6, true);

		practiceText = createInfoText(cfg('infoTexts.practice', null), Language.getPhrase("Practice Mode").toUpperCase(), 116, 32, 0, false);
		if(practiceText != null) practiceText.visible = PlayState.instance.practiceMode;

		var chartingText:FlxText = createInfoText(cfg('infoTexts.charting', null), Language.getPhrase("Charting Mode").toUpperCase(), null, 32, 0, false);
		if(chartingText != null) chartingText.visible = PlayState.chartingMode;

		var extras:Dynamic = cfg('extraTexts', null);
		if(extras != null && Std.isOfType(extras, Array))
		{
			var extraList:Array<Dynamic> = cast extras;
			for (i => def in extraList)
				createInfoText(def, '', 148 + (i * 34), 28, 0.75 + (i * 0.1), true);
		}

		FlxTween.tween(bg, {alpha: cfgFloat('background.alpha', 0.6)}, cfgFloat('background.fadeTime', 0.4), {ease: FlxEase.quartInOut});

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		addUI(grpMenuShit);

		createCursor();

		missingTextBG = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		missingTextBG.scale.set(FlxG.width, FlxG.height);
		missingTextBG.updateHitbox();
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		addUI(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font(fontName), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		addUI(missingText);

		regenMenu();
		applyBlur();
	}

	function addUI<T:FlxBasic>(obj:T):T
	{
		uiObjects.push(obj);
		add(obj);
		return obj;
	}

	function clearUI():Void
	{
		if(grpMenuShit != null)
			for (item in grpMenuShit.members) if(item != null) FlxTween.cancelTweensOf(item);

		for (obj in uiObjects)
		{
			FlxTween.cancelTweensOf(obj);
			remove(obj, true);
			obj.destroy();
		}
		uiObjects = [];
		infoTexts = [];
		infoTextTo = [];
		grpMenuShit = null;
		skipTimeText = null;
		skipTimeTracker = null;
		practiceText = null;
		cursor = null;
		bg = null;
		clearBlur();
	}

	/** F6 (or whatever "hotReloadKey" says): re-read the JSON and rebuild the pause UI in place. */
	function hotReload():Void
	{
		clearUI();
		loadConfig();
		buildMenuList();
		buildUI();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		trace('Reloaded pauseMenu.json');
	}

	// ---------------------------------------------------------------------
	//  JSON config (data/pauseMenu.json)
	// ---------------------------------------------------------------------

	/** Looks for data/<song>/pauseMenu.json first, then data/pauseMenu.json (mods override assets). */
	function loadMenuData():Void
	{
		menuData = null;
		var songPath:String = Paths.formatToSongPath(PlayState.SONG.song);
		for (file in ['data/$songPath/pauseMenu.json', 'data/pauseMenu.json'])
		{
			try
			{
				var raw:String = Paths.getTextFromFile(file);
				if(raw == null || raw.trim().length < 1) continue;
				menuData = Json.parse(raw);
				break;
			}
			catch(e:Dynamic)
			{
				warn('Error parsing $file: $e');
			}
		}
	}

	function warn(msg:String):Void
		trace('[pauseMenu.json] $msg');

	/** Warns about misspelled / unknown keys and wrongly-typed sections. */
	function validateConfig():Void
	{
		if(menuData == null) return;

		checkKeys(menuData, KEYS_ROOT, 'root');
		checkSection('animations', KEYS_ANIM);
		checkSection('background', KEYS_BG);
		checkSection('menu', KEYS_MENU);
		checkSection('cursor', KEYS_CURSOR);
		checkSection('sounds', KEYS_SOUNDS);
		checkSection('music', KEYS_MUSIC);
		checkSection('infoTexts', KEYS_INFOTEXTS);

		for (key in KEYS_INFOTEXTS)
		{
			var def:Dynamic = cfg('infoTexts.$key', null);
			if(def != null) checkKeys(def, KEYS_TEXT, 'infoTexts.$key');
		}

		var extras:Dynamic = cfg('extraTexts', null);
		if(extras != null)
		{
			if(!Std.isOfType(extras, Array)) warn('"extraTexts" must be an array');
			else
			{
				var list:Array<Dynamic> = cast extras;
				for (i => def in list) checkKeys(def, KEYS_TEXT, 'extraTexts[$i]');
			}
		}

		var items:Dynamic = cfg('menuItems', null);
		if(items != null && Std.isOfType(items, Array))
		{
			var list:Array<Dynamic> = cast items;
			for (i => entry in list)
				if(!Std.isOfType(entry, String)) checkKeys(entry, KEYS_ITEM, 'menuItems[$i]');
		}
	}

	function checkSection(name:String, valid:Array<String>):Void
	{
		var section:Dynamic = cfg(name, null);
		if(section != null) checkKeys(section, valid, name);
	}

	function checkKeys(obj:Dynamic, valid:Array<String>, where:String):Void
	{
		if(!Reflect.isObject(obj) || Std.isOfType(obj, Array) || Std.isOfType(obj, String))
		{
			warn('"$where" should be an object { ... }');
			return;
		}
		for (k in Reflect.fields(obj))
		{
			if(valid.contains(k)) continue;
			var hint:String = '';
			for (v in valid) if(v.toLowerCase() == k.toLowerCase()) hint = ' Did you mean "$v"?';
			warn('Unknown key "$k" in $where.$hint Valid keys: ${valid.join(", ")}');
		}
	}

	/** Reads a value by dot path from any object, e.g. cfgIn(def, 'a.b', 0). Returns def if missing. */
	function cfgIn(root:Dynamic, path:String, def:Dynamic):Dynamic
	{
		var cur:Dynamic = root;
		for (key in path.split('.'))
		{
			if(cur == null || !Reflect.isObject(cur) || !Reflect.hasField(cur, key)) return def;
			cur = Reflect.field(cur, key);
		}
		return (cur == null) ? def : cur;
	}

	function inFloat(root:Dynamic, path:String, def:Float):Float
	{
		var v:Dynamic = cfgIn(root, path, null);
		if(v == null) return def;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	function inBool(root:Dynamic, path:String, def:Bool):Bool
	{
		var v:Dynamic = cfgIn(root, path, null);
		return (v != null && Std.isOfType(v, Bool)) ? v : def;
	}

	function inString(root:Dynamic, path:String, def:String):String
	{
		var v:Dynamic = cfgIn(root, path, null);
		return (v == null) ? def : Std.string(v);
	}

	/** Accepts "#RRGGBB", "0xAARRGGBB", or color names like "WHITE". */
	function inColor(root:Dynamic, path:String, def:FlxColor):FlxColor
	{
		var v:Dynamic = cfgIn(root, path, null);
		if(v == null) return def;
		var c:Null<FlxColor> = FlxColor.fromString(Std.string(v));
		return (c == null) ? def : c;
	}

	/** Lower-cased string that must be one of `valid`; otherwise warns and returns def. */
	function inEnum(root:Dynamic, path:String, def:String, valid:Array<String>):String
	{
		var v:String = inString(root, path, def).toLowerCase();
		if(!valid.contains(v))
		{
			warn('"$path" is "$v" but must be one of: ${valid.join(", ")}');
			return def;
		}
		return v;
	}

	// shortcuts that read from the root of the loaded JSON
	inline function cfg(path:String, def:Dynamic):Dynamic return cfgIn(menuData, path, def);
	inline function cfgFloat(path:String, def:Float):Float return inFloat(menuData, path, def);
	inline function cfgBool(path:String, def:Bool):Bool return inBool(menuData, path, def);
	inline function cfgString(path:String, def:String):String return inString(menuData, path, def);
	inline function cfgColor(path:String, def:FlxColor):FlxColor return inColor(menuData, path, def);

	/**
	 * Builds the base menu list. Entries in "menuItems" are either
	 *   "Resume"                                     (built-in item)
	 *   { "id": "...", "label": "...", "action": "...", "showWhen": [...] }   (custom item or customized built-in)
	 */
	function getBaseMenuItems():Array<String>
	{
		var list:Dynamic = cfg('menuItems', null);
		if(list == null) return DEFAULT_ITEMS.copy();
		if(!Std.isOfType(list, Array))
		{
			warn('"menuItems" must be an array');
			return DEFAULT_ITEMS.copy();
		}

		var out:Array<String> = [];
		var arr:Array<Dynamic> = cast list;
		for (entry in arr)
		{
			var id:String = null;
			var def:Dynamic = null;
			if(Std.isOfType(entry, String)) id = entry;
			else if(Reflect.isObject(entry))
			{
				def = entry;
				id = inString(entry, 'id', null);
			}

			if(id == null)
			{
				warn('A "menuItems" entry needs to be a string or an object with an "id"');
				continue;
			}
			if(def != null && !checkShowWhen(cfgIn(def, 'showWhen', null))) continue;

			var isCustom:Bool = (def != null && Reflect.hasField(def, 'action'));
			if(!isCustom && !DEFAULT_ITEMS.contains(id))
			{
				warn('Unknown menu item "$id". Built-in items: ${DEFAULT_ITEMS.join(", ")} (or add an "action" to make a custom item)');
				continue;
			}

			if(def != null) itemDefs.set(id, def);
			out.push(id);
		}
		return (out.length > 0) ? out : DEFAULT_ITEMS.copy();
	}

	function getItemLabel(id:String):String
	{
		var label:String = inString(itemDefs.get(id), 'label', null);
		if(label != null) return label;

		var labels:Dynamic = cfg('labels', null);
		if(labels != null && Reflect.isObject(labels) && Reflect.hasField(labels, id))
			return Std.string(Reflect.field(labels, id));

		return Language.getPhrase('pause_$id', id);
	}

	/**
	 * "showWhen": "charting" or ["freeplay", "!practice"]. All conditions must hold.
	 * Conditions: story, freeplay, charting, practice, botplay. Prefix with ! to negate.
	 */
	function checkShowWhen(v:Dynamic):Bool
	{
		if(v == null) return true;
		var conds:Array<Dynamic> = Std.isOfType(v, Array) ? cast v : [v];
		for (c in conds)
		{
			var s:String = Std.string(c).trim().toLowerCase();
			var negate:Bool = s.startsWith('!');
			if(negate) s = s.substr(1);

			var known:Bool = true;
			var result:Bool = false;
			switch(s)
			{
				case 'story': result = PlayState.isStoryMode;
				case 'freeplay': result = !PlayState.isStoryMode;
				case 'charting': result = PlayState.chartingMode;
				case 'practice': result = PlayState.instance.practiceMode;
				case 'botplay': result = PlayState.instance.cpuControlled;
				default: known = false;
			}
			if(!known)
			{
				warn('Unknown showWhen condition "$c" (valid: story, freeplay, charting, practice, botplay)');
				continue;
			}
			if(result == negate) return false;
		}
		return true;
	}

	/** Replaces {tags} in info texts. */
	function fillTags(s:String):String
	{
		if(s.indexOf('{') < 0) return s;

		var inst:PlayState = PlayState.instance;
		var songLength:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 0;
		var accuracy:Float = Math.floor(inst.ratingPercent * 10000) / 100;

		return s.replace('{song}', PlayState.SONG.song)
			.replace('{difficulty}', Difficulty.getString().toUpperCase())
			.replace('{deaths}', Std.string(PlayState.deathCounter))
			.replace('{score}', Std.string(inst.songScore))
			.replace('{misses}', Std.string(inst.songMisses))
			.replace('{accuracy}', Std.string(accuracy))
			.replace('{rating}', Std.string(inst.ratingName))
			.replace('{fc}', Std.string(inst.ratingFC))
			.replace('{combo}', Std.string(inst.combo))
			.replace('{songTime}', FlxStringUtil.formatTime(Math.max(0, Math.floor(Conductor.songPosition / 1000)), false))
			.replace('{songLength}', FlxStringUtil.formatTime(Math.max(0, Math.floor(songLength / 1000)), false))
			.replace('{mod}', (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '')
			.replace('{botplay}', inst.cpuControlled ? 'ON' : 'OFF');
	}

	// ---------------------------------------------------------------------
	//  Visuals
	// ---------------------------------------------------------------------

	function createBackground():Void
	{
		bg = new FlxSprite().makeGraphic(1, 1, cfgColor('background.color', FlxColor.BLACK));

		var img:String = cfgString('background.image', null);
		var usedImage:Bool = false;
		if(img != null && img.length > 0)
		{
			var graphic = Paths.image(img);
			if(graphic != null)
			{
				bg.loadGraphic(graphic);
				usedImage = true;
			}
			else warn('background.image "$img" was not found in images/');
		}

		if(usedImage)
		{
			bg.color = cfgColor('background.tint', FlxColor.WHITE);
			switch(inEnum(menuData, 'background.scaleMode', 'fill', ['fill', 'stretch', 'none']))
			{
				case 'stretch':
					bg.setGraphicSize(FlxG.width, FlxG.height);
					bg.updateHitbox();
				case 'none':
					bg.updateHitbox();
				default: // fill: cover the whole screen, keep aspect ratio
					var s:Float = Math.max(FlxG.width / bg.frameWidth, FlxG.height / bg.frameHeight);
					bg.scale.set(s, s);
					bg.updateHitbox();
			}
			bg.screenCenter();
		}
		else
		{
			bg.scale.set(FlxG.width, FlxG.height);
			bg.updateHitbox();
		}

		bg.blend = parseBlend(cfgString('background.blend', 'normal'));
		bg.alpha = 0;
		bg.scrollFactor.set();
		addUI(bg);
	}

	function parseBlend(name:String):BlendMode
	{
		return switch(name.toLowerCase())
		{
			case 'normal': BlendMode.NORMAL;
			case 'add': BlendMode.ADD;
			case 'multiply': BlendMode.MULTIPLY;
			case 'screen': BlendMode.SCREEN;
			case 'overlay': BlendMode.OVERLAY;
			case 'lighten': BlendMode.LIGHTEN;
			case 'darken': BlendMode.DARKEN;
			case 'difference': BlendMode.DIFFERENCE;
			case 'hardlight': BlendMode.HARDLIGHT;
			case 'invert': BlendMode.INVERT;
			case 'subtract': BlendMode.SUBTRACT;
			default:
			{
				warn('Unknown background.blend "$name" (valid: normal, add, multiply, screen, overlay, lighten, darken, difference, hardlight, invert, subtract)');
				BlendMode.NORMAL;
			}
		}
	}

	/** Blurs the gameplay cameras behind the pause menu. Off by default ("background.blur": 0). */
	function applyBlur():Void
	{
		var amount:Float = cfgFloat('background.blur', 0);
		if(amount <= 0 || PlayState.instance == null) return;

		var filters:Array<BitmapFilter> = [new BlurFilter(amount, amount, 2)];
		for (cam in [PlayState.instance.camGame, PlayState.instance.camHUD])
			if(cam != null) cam.setFilters(filters);
		blurApplied = true;
	}

	function clearBlur():Void
	{
		if(!blurApplied || PlayState.instance == null) return;
		for (cam in [PlayState.instance.camGame, PlayState.instance.camHUD])
			if(cam != null) cam.setFilters([]);
		blurApplied = false;
	}

	/** Builds one info text from its JSON object. `def` may be null (= all defaults). */
	function createInfoText(def:Dynamic, defText:String, defY:Null<Float>, defSize:Int, defDelay:Float, defSlide:Bool):FlxText
	{
		if(!inBool(def, 'visible', true) || !checkShowWhen(cfgIn(def, 'showWhen', null))) return null;

		var size:Int = Std.int(inFloat(def, 'size', defSize));
		var txt:FlxText = new FlxText(0, 0, 0, fillTags(inString(def, 'text', defText)), size);
		txt.scrollFactor.set();
		txt.setFormat(Paths.font(fontName), size, inColor(def, 'color', FlxColor.WHITE));
		txt.updateHitbox();

		var finalX:Float = switch(inEnum(def, 'align', 'right', ['left', 'center', 'right']))
		{
			case 'left': 20;
			case 'center': (FlxG.width - txt.width) / 2;
			default: FlxG.width - (txt.width + 20);
		}
		finalX += inFloat(def, 'offsetX', 0);
		var finalY:Float = inFloat(def, 'y', (defY != null) ? defY : FlxG.height - (txt.height + 20)) + inFloat(def, 'offsetY', 0);

		var from:String = inEnum(def, 'slideFrom', 'right', DIRECTIONS);
		var to:String = inEnum(def, 'slideTo', from, DIRECTIONS);

		if(cfgBool('animations.slideIn', true) && inBool(def, 'slideIn', defSlide))
		{
			txt.alpha = 0;
			switch(from)
			{
				case 'left': txt.setPosition(-txt.width - 40, finalY - 5);
				case 'top': txt.setPosition(finalX, -txt.height - 40);
				case 'bottom': txt.setPosition(finalX, FlxG.height + 40);
				default: txt.setPosition(FlxG.width + 40, finalY - 5);
			}
			FlxTween.tween(txt, {alpha: 1, y: finalY, x: finalX}, 0.6, {ease: FlxEase.quartOut, startDelay: inFloat(def, 'delay', defDelay)});
		}
		else
			txt.setPosition(finalX, finalY);

		infoTexts.push(txt);
		infoTextTo.push(to);
		addUI(txt);
		return txt;
	}

	function createCursor():Void
	{
		cursor = null;
		if(!cfgBool('cursor.visible', false)) return;

		var img:String = cfgString('cursor.image', null);
		var graphic = (img != null && img.length > 0) ? Paths.image(img) : null;
		if(graphic != null)
		{
			cursor = new FlxSprite().loadGraphic(graphic);
			var sc:Float = cfgFloat('cursor.scale', 1);
			cursor.scale.set(sc, sc);
			cursor.updateHitbox();
			cursor.color = cfgColor('cursor.color', FlxColor.WHITE);
		}
		else
		{
			var size:Int = Std.int(cfgFloat('cursor.size', 64));
			var t:FlxText = new FlxText(0, 0, 0, cfgString('cursor.text', '>'), size);
			t.setFormat(Paths.font(fontName), size, cfgColor('cursor.color', FlxColor.WHITE), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 2;
			cursor = t;
		}
		cursor.scrollFactor.set();
		cursor.visible = false;
		addUI(cursor);
	}

	/** Keeps the cursor next to the currently selected item. */
	function updateCursor():Void
	{
		if(cursor == null || grpMenuShit == null) return;

		var sel:Alphabet = null;
		for (item in grpMenuShit.members)
			if(item != null && item.targetY == 0) { sel = item; break; }

		cursor.visible = (sel != null);
		if(sel == null) return;

		cursor.x = sel.x + cfgFloat('cursor.offsetX', -60);
		cursor.y = sel.y + ((sel.height - cursor.height) / 2) + cfgFloat('cursor.offsetY', 0);
	}

	function playCfgSound(key:String, def:String, defVolume:Float):Void
	{
		var name:String = cfgString('sounds.$key', def);
		if(name == null || name.length < 1 || name.toLowerCase() == 'none') return;
		FlxG.sound.play(Paths.sound(name), cfgFloat('sounds.${key}Volume', defVolume));
	}

	function getPauseSong()
	{
		// "music.track" in the JSON wins over everything ("none" = silence)
		var jsonTrack:String = cfgString('music.track', null);
		if(jsonTrack != null)
		{
			var formattedTrack:String = Paths.formatToSongPath(jsonTrack);
			return (formattedTrack == 'none' || formattedTrack == '') ? null : formattedTrack;
		}

		var formattedSongName:String = (songName != null ? Paths.formatToSongPath(songName) : '');
		var formattedPauseMusic:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
		if(formattedSongName == 'none' || (formattedSongName != 'none' && formattedPauseMusic == 'none')) return null;

		return (formattedSongName != '') ? formattedSongName : formattedPauseMusic;
	}

	// ---------------------------------------------------------------------
	//  Update / input
	// ---------------------------------------------------------------------

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;
	override function update(elapsed:Float)
	{
		cantUnpause -= elapsed;
		if (pauseMusic.volume < maxMusicVolume)
			pauseMusic.volume += musicFadeSpeed * elapsed;

		super.update(elapsed);
		updateCursor();

		if(closing) return; // slide-out animation playing, ignore input

		if(controls.BACK)
		{
			slideOutAndClose();
			return;
		}

		if(FlxG.keys.justPressed.F5)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			PlayState.nextReloadAll = true;
			MusicBeatState.resetState();
		}

		if(reloadKey != FlxKey.NONE && FlxG.keys.anyJustPressed([reloadKey]))
		{
			hotReload();
			return;
		}

		updateSkipTextStuff();
		if (controls.UI_UP_P)
		{
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1);
		}

		var daSelected:String = menuItems[curSelected];
		switch (daSelected)
		{
			case 'Skip Time':
				if (controls.UI_LEFT_P)
				{
					playCfgSound('scroll', 'scrollMenu', 0.4);
					curTime -= 1000;
					holdTime = 0;
				}
				if (controls.UI_RIGHT_P)
				{
					playCfgSound('scroll', 'scrollMenu', 0.4);
					curTime += 1000;
					holdTime = 0;
				}

				if(controls.UI_LEFT || controls.UI_RIGHT)
				{
					holdTime += elapsed;
					if(holdTime > 0.5)
					{
						curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
					}

					if(curTime >= FlxG.sound.music.length) curTime -= FlxG.sound.music.length;
					else if(curTime < 0) curTime += FlxG.sound.music.length;
					updateSkipTimeText();
				}
		}

		if (controls.ACCEPT && (cantUnpause <= 0 || !controls.controllerMode))
		{
			var inDifficultyMenu:Bool = (menuItems == difficultyChoices);
			playCfgSound('confirm', '', 0.7);

			// Custom items from the JSON
			if(!inDifficultyMenu && itemDefs.exists(daSelected) && Reflect.hasField(itemDefs.get(daSelected), 'action'))
			{
				runCustomAction(daSelected, itemDefs.get(daSelected));
				return;
			}

			if (inDifficultyMenu)
			{
				var songLowercase:String = Paths.formatToSongPath(PlayState.SONG.song);
				var poop:String = Highscore.formatSong(songLowercase, curSelected);
				try
				{
					if(menuItems.length - 1 != curSelected && difficultyChoices.contains(daSelected))
					{
						Song.loadFromJson(poop, songLowercase);
						PlayState.storyDifficulty = curSelected;
						MusicBeatState.resetState();
						FlxG.sound.music.volume = 0;
						PlayState.changedDifficulty = true;
						PlayState.chartingMode = false;
						return;
					}
				}
				catch(e:haxe.Exception)
				{
					trace('ERROR! ${e.message}');

					var errorStr:String = e.message;
					if(errorStr.startsWith('[lime.utils.Assets] ERROR:')) errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length-1); //Missing chart
					else errorStr += '\n\n' + e.stack;

					missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));

					super.update(elapsed);
					return;
				}


				menuItems = menuItemsOG;
				regenMenu();
			}

			switch (daSelected)
			{
				case "Resume":
					slideOutAndClose();
				case 'Change Difficulty':
					menuItems = difficultyChoices;
					deleteSkipTimeText();
					regenMenu();
				case 'Toggle Practice Mode':
					PlayState.instance.practiceMode = !PlayState.instance.practiceMode;
					PlayState.changedDifficulty = true;
					if(practiceText != null) practiceText.visible = PlayState.instance.practiceMode;
				case "Restart Song":
					restartSong();
				case "Leave Charting Mode":
					restartSong();
					PlayState.chartingMode = false;
				case 'Skip Time':
					if(curTime < Conductor.songPosition)
					{
						PlayState.startOnTime = curTime;
						restartSong(true);
					}
					else
					{
						if (curTime != Conductor.songPosition)
						{
							PlayState.instance.clearNotesBefore(curTime);
							PlayState.instance.setSongTime(curTime);
						}
						close();
					}
				case 'End Song':
					close();
					PlayState.instance.notes.clear();
					PlayState.instance.unspawnNotes = [];
					PlayState.instance.finishSong(true);
				case 'Toggle Botplay':
					PlayState.instance.cpuControlled = !PlayState.instance.cpuControlled;
					PlayState.changedDifficulty = true;
					PlayState.instance.botplayTxt.visible = PlayState.instance.cpuControlled;
					PlayState.instance.botplayTxt.alpha = 1;
					PlayState.instance.botplaySine = 0;
				case 'Options':
					PlayState.instance.paused = true; // For lua
					PlayState.instance.vocals.volume = 0;
					PlayState.instance.canResync = false;
					MusicBeatState.switchState(new OptionsState());

					// Keep the same pause music going in the options menu ("music.track" if set, otherwise the player's setting)
					var optionsTrack:String = (cfgString('music.track', null) != null) ? getPauseSong() : (ClientPrefs.data.pauseMusic != 'None' ? Paths.formatToSongPath(ClientPrefs.data.pauseMusic) : null);
					if(optionsTrack != null)
					{
						FlxG.sound.playMusic(Paths.music(optionsTrack), pauseMusic.volume);
						FlxTween.tween(FlxG.sound.music, {volume: 1}, 0.8);
						FlxG.sound.music.time = pauseMusic.time;
					}
					OptionsState.onPlayState = true;
				case "Exit to menu":
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
					PlayState.deathCounter = 0;
					PlayState.seenCutscene = false;

					PlayState.instance.canResync = false;
					Mods.loadTopMod();
					if(PlayState.isStoryMode)
						MusicBeatState.switchState(new StoryMenuState());
					else
						MusicBeatState.switchState(new FreeplayState());

					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					FlxG.camera.followLerp = 0;
			}
		}
	}

	/**
	 * Runs a custom menu item's "action":
	 *   resume | close | restart | chartEditor
	 *   switchState  ("state": "states.MainMenuState" or just "MainMenuState", optional "menuMusic": false)
	 *   openUrl      ("url": "https://...")
	 *   playSound    ("sound": "confirmMenu")
	 *   script       ("callback": "onPauseMenuItem", "args": anything) -> calls Lua/HScript callback(id, args)
	 * Add "closeAfter": true to also close the pause menu afterwards (for openUrl / playSound / script).
	 */
	function runCustomAction(id:String, def:Dynamic):Void
	{
		var action:String = inString(def, 'action', '');
		switch(action.toLowerCase())
		{
			case 'resume' | 'close':
				slideOutAndClose();
				return;
			case 'restart':
				restartSong();
				return;
			case 'charteditor':
				@:privateAccess PlayState.instance.openChartEditor();
				return;
			case 'switchstate':
				var path:String = inString(def, 'state', null);
				var cls:Class<Dynamic> = null;
				if(path != null) cls = Type.resolveClass((path.indexOf('.') >= 0) ? path : 'states.' + path);
				if(cls == null)
				{
					warn('Item "$id": state "$path" could not be found (use the full path, e.g. "states.MainMenuState")');
					FlxG.sound.play(Paths.sound('cancelMenu'));
					return;
				}

				PlayState.instance.canResync = false;
				PlayState.deathCounter = 0;
				PlayState.seenCutscene = false;
				PlayState.changedDifficulty = false;
				PlayState.chartingMode = false;
				FlxG.camera.followLerp = 0;
				Mods.loadTopMod();

				var nextState:Dynamic = Type.createInstance(cls, []);
				MusicBeatState.switchState(nextState);
				if(inBool(def, 'menuMusic', true)) FlxG.sound.playMusic(Paths.music('freakyMenu'));
				return;
			case 'openurl':
				var url:String = inString(def, 'url', null);
				if(url != null) CoolUtil.browserLoad(url);
				else warn('Item "$id": openUrl needs a "url"');
			case 'playsound':
				var snd:String = inString(def, 'sound', null);
				if(snd != null) FlxG.sound.play(Paths.sound(snd));
				else warn('Item "$id": playSound needs a "sound"');
			case 'script':
				PlayState.instance.callOnScripts(inString(def, 'callback', 'onPauseMenuItem'), [id, cfgIn(def, 'args', null)]);
			default:
				warn('Item "$id": unknown action "$action" (valid: resume, close, restart, chartEditor, switchState, openUrl, playSound, script)');
				FlxG.sound.play(Paths.sound('cancelMenu'));
		}

		if(inBool(def, 'closeAfter', false)) slideOutAndClose();
	}

	/** Slides everything off-screen (if "animations.slideOut" is true) and then closes. Otherwise closes instantly. */
	function slideOutAndClose():Void
	{
		if(closing) return;
		if(!cfgBool('animations.slideOut', true))
		{
			close();
			return;
		}

		closing = true;
		deleteSkipTimeText();
		var time:Float = cfgFloat('animations.slideOutTime', 0.3);
		if(time <= 0)
		{
			close();
			return;
		}

		FlxTween.cancelTweensOf(bg);
		FlxTween.tween(bg, {alpha: 0}, time, {ease: FlxEase.quartIn});
		if(cursor != null) FlxTween.tween(cursor, {alpha: 0}, time, {ease: FlxEase.quartIn});

		for (i => txt in infoTexts)
		{
			FlxTween.cancelTweensOf(txt);
			var props:Dynamic = switch(infoTextTo[i])
			{
				case 'left': {x: -txt.width - 40, alpha: 0};
				case 'top': {y: -txt.height - 40, alpha: 0};
				case 'bottom': {y: FlxG.height + 40, alpha: 0};
				default: {x: FlxG.width + 40, alpha: 0};
			}
			FlxTween.tween(txt, props, time, {ease: FlxEase.quartIn});
		}

		var menuFrom:String = inEnum(menuData, 'menu.slideFrom', 'left', DIRECTIONS);
		var menuTo:String = inEnum(menuData, 'menu.slideTo', menuFrom, DIRECTIONS);
		for (num => item in grpMenuShit.members)
		{
			item.isMenuItem = false; // stop Alphabet's own lerp from fighting the tween
			var props:Dynamic = switch(menuTo)
			{
				case 'right': {x: FlxG.width + 40 + (num * 20)};
				case 'top': {y: -item.height - 40};
				case 'bottom': {y: FlxG.height + 40};
				default: {x: -item.width - 40 - (num * 20)};
			}
			FlxTween.tween(item, props, time, {ease: FlxEase.quartIn});
		}

		new FlxTimer().start(time, function(_) close());
	}

	function deleteSkipTimeText()
	{
		if(skipTimeText != null)
		{
			skipTimeText.kill();
			remove(skipTimeText);
			uiObjects.remove(skipTimeText);
			skipTimeText.destroy();
		}
		skipTimeText = null;
		skipTimeTracker = null;
	}

	public static function restartSong(noTrans:Bool = false)
	{
		PlayState.instance.paused = true; // For lua
		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;

		if(noTrans)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function close()
	{
		clearBlur();
		super.close();
	}

	override function destroy()
	{
		clearBlur();
		pauseMusic.destroy();
		super.destroy();
	}

	function changeSelection(change:Int = 0):Void
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, menuItems.length - 1);
		for (num => item in grpMenuShit.members)
		{
			item.targetY = num - curSelected;
			item.alpha = inactiveAlpha;
			item.color = menuColor;
			if(selectedScale != 1) item.setScale(1);
			if (item.targetY == 0)
			{
				item.alpha = 1;
				item.color = selectedColor;
				if(selectedScale != 1) item.setScale(selectedScale);
				if(item == skipTimeTracker)
				{
					curTime = Math.max(0, Conductor.songPosition);
					updateSkipTimeText();
				}
			}
		}
		missingText.visible = false;
		missingTextBG.visible = false;
		playCfgSound('scroll', 'scrollMenu', 0.4);
	}

	function regenMenu():Void {
		for (i in 0...grpMenuShit.members.length)
		{
			var obj:Alphabet = grpMenuShit.members[0];
			obj.kill();
			grpMenuShit.remove(obj, true);
			obj.destroy();
		}

		var align:String = inEnum(menuData, 'menu.align', 'left', ['left', 'center', 'right']);
		var marginX:Float = cfgFloat('menu.x', 90);
		var offsetX:Float = cfgFloat('menu.offsetX', 0);
		var startY:Float = cfgFloat('menu.y', 320);
		var distX:Float = cfgFloat('menu.distanceX', (align == 'left') ? 20 : 0); // no staircase effect when centered / right-aligned
		var distY:Float = cfgFloat('menu.distanceY', 120);
		var stagger:Float = cfgFloat('menu.slideStagger', 80);
		var slideIn:Bool = cfgBool('animations.slideIn', true) && cfgBool('menu.slideIn', true);
		var slideFrom:String = inEnum(menuData, 'menu.slideFrom', 'left', DIRECTIONS);

		for (num => str in menuItems) {
			var item = new Alphabet(marginX, startY, getItemLabel(str), true);
			item.isMenuItem = true;
			item.targetY = num;
			item.distancePerItem.set(distX, distY);

			var baseX:Float = switch(align)
			{
				case 'center': (FlxG.width - item.width) / 2;
				case 'right': FlxG.width - item.width - marginX;
				default: marginX;
			}
			baseX += offsetX;
			item.startPosition.x = baseX;
			item.x = baseX;

			if(slideIn)
			{
				// starts off-screen; Alphabet's menu lerp slides it in smoothly, staggered per item
				switch(slideFrom)
				{
					case 'right': item.x = FlxG.width + (num * stagger);
					case 'top': item.y = -item.height - (num * stagger);
					case 'bottom': item.y = FlxG.height + (num * stagger);
					default: item.x = -item.width - (num * stagger);
				}
			}
			grpMenuShit.add(item);

			if(str == 'Skip Time')
			{
				skipTimeText = new FlxText(0, 0, 0, '', 64);
				skipTimeText.setFormat(Paths.font(fontName), 64, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				skipTimeText.scrollFactor.set();
				skipTimeText.borderSize = 2;
				skipTimeTracker = item;
				addUI(skipTimeText);

				updateSkipTextStuff();
				updateSkipTimeText();
			}
		}
		curSelected = 0;
		changeSelection();
	}

	function updateSkipTextStuff()
	{
		if(skipTimeText == null || skipTimeTracker == null) return;

		skipTimeText.x = skipTimeTracker.x + skipTimeTracker.width + 60;
		skipTimeText.y = skipTimeTracker.y;
		skipTimeText.visible = (skipTimeTracker.alpha >= 1);
	}

	function updateSkipTimeText()
		skipTimeText.text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false) + ' / ' + FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
}
