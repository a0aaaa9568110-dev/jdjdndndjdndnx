package states;

import flixel.FlxObject;
import flixel.effects.FlxFlicker;
import lime.app.Application;
import states.editors.MasterEditorMenu;
import options.OptionsState;
import haxe.Json;

enum MainMenuColumn {
	LEFT;
	CENTER;
	RIGHT;
}

// Settings for a single menu item (read from data/mainmenu.json)
typedef MenuItemConfig = {
	var name:String;
	var enabled:Bool;
	var x:Null<Float>; // null = use the automatic layout position
	var y:Null<Float>;
	var offsetX:Float; // added on top of x / the automatic position
	var offsetY:Float;
	var scale:Float;
	var anchor:String; // "left" = x is measured from the left edge, "right" = x is measured from the right edge
	var angle:Float;
	var flipX:Bool;
	var flipY:Bool;
	var color:String; // hex tint like "FF0000", null = none
	var antialiasing:Null<Bool>; // null = use the player's antialiasing setting
	var fps:Float; // 0 = default (24)
	var image:String; // atlas path, null = mainmenu/menu_<name>
	var idleAnim:String; // animation prefix, null = "<name> idle"
	var selectedAnim:String; // animation prefix, null = "<name> selected"
	var state:String; // class to open when picked, e.g. "states.CreditsState"
	var url:String; // link to open when picked
}

// Settings for the slide in / slide out animations
typedef SlideConfig = {
	var enabled:Bool;
	var duration:Float;
	var stagger:Float;
	var ease:String;
	var direction:String; // auto, left, right, up, down
}

class MainMenuState extends MusicBeatState
{
	public static var psychEngineVersion:String = '1.0.4'; // This is also used for Discord RPC
	public static var curSelected:Int = 0;
	public static var curColumn:MainMenuColumn = CENTER;
	var allowMouse:Bool = true; //Turn this off to block mouse movement in menus

	static var lastBG:Int = -1; // Remembers the last background so you don't get the same one twice in a row

	var menuItems:FlxTypedGroup<FlxSprite>;
	var leftItem:FlxSprite;
	var rightItem:FlxSprite;

	//Centered/Text options
	var optionShit:Array<String> = [];

	var leftOption:String = null;
	var rightOption:String = null;

	var magenta:FlxSprite;
	var camFollow:FlxObject;

	// ---- Config (filled by loadConfig from data/mainmenu.json) ----
	var json:Dynamic;
	var mainItemConfigs:Array<MenuItemConfig> = [];
	var leftConfig:MenuItemConfig;
	var rightConfig:MenuItemConfig;
	var slideInConfig:SlideConfig;
	var slideOutConfig:SlideConfig;

	var bgCount:Int = 15;
	var bgRandomize:Bool = true;
	var bgFixed:Int = 1;
	var bgScale:Float = 1.175;
	var bgX:Float = -80;
	var bgY:Float = 0;

	var scrollY:Float = 0.25;
	var followLerp:Float = 0.15;
	var followSelected:Bool = true;

	var mainX:Float = 60;
	var mainY:Float = 90;
	var mainSpacing:Float = 140;
	var mainBalance:Bool = true;
	var mainScale:Float = 1;

	var camZoom:Float = 1;
	var followOffsetY:Float = 0;

	var spacingX:Float = 0;

	var bgImagePrefix:String = 'menuart/menuBG';
	var bgAlpha:Float = 1;
	var bgColor:FlxColor = FlxColor.WHITE;

	// Selected / unselected look
	var selScale:Float = 1; // scale multiplier of the highlighted item
	var selAlpha:Float = 1;
	var unselAlpha:Float = 1;
	var selTween:Float = 0; // seconds to blend between selected/unselected (0 = instant)
	var wrapSelection:Bool = true;

	// Confirm behaviour
	var flickerEnabled:Bool = true;
	var flickerDuration:Float = 1;
	var flickerInterval:Float = 0.06;
	var flashEnabled:Bool = true;
	var flashDuration:Float = 1.1;
	var flashInterval:Float = 0.15;
	var flashColor:FlxColor = FlxColor.WHITE;
	var fadeOthers:Bool = false;
	var fadeDuration:Float = 0.4;

	// Sounds (empty string = silent)
	var sndScroll:String = 'scrollMenu';
	var sndConfirm:String = 'confirmMenu';
	var sndCancel:String = 'cancelMenu';

	// Version text
	var showPsychVer:Bool = true;
	var showFnfVer:Bool = true;
	var verX:Float = 12;
	var verBottom:Float = 44;
	var verSize:Int = 16;
	var verColor:FlxColor = FlxColor.WHITE;

	var decorations:Array<Dynamic> = [];
	var baseScales:Map<FlxSprite, Float> = new Map();
	var customStates:Map<String, String> = new Map();
	var customUrls:Map<String, String> = new Map();

	static var showOutdatedWarning:Bool = true;
	override function create()
	{
		super.create();

		#if MODS_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		loadConfig();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the MainMenu", null);
		#end

		persistentUpdate = persistentDraw = true;

		var yScroll:Float = scrollY;

		// Pick a random background, avoiding the one used last time (or use a fixed one)
		var bgNum:Int = bgFixed;
		if (bgRandomize)
		{
			bgNum = FlxG.random.int(1, bgCount, lastBG > 0 ? [lastBG] : null);
			lastBG = bgNum;
		}

		var bg:FlxSprite = new FlxSprite(bgX, bgY).loadGraphic(Paths.image(bgImagePrefix + bgNum));
		bg.alpha = bgAlpha;
		bg.color = bgColor;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set(0, yScroll);
		bg.setGraphicSize(Std.int(bg.width * bgScale));
		bg.updateHitbox();
		bg.screenCenter();
		bg.x += bgX + 80; // screenCenter overrides x/y, so re-apply the JSON offset (-80 is the old default = no change)
		bg.y += bgY;
		add(bg);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);

		magenta = new FlxSprite(-80).loadGraphic(Paths.image('blank'));
		magenta.antialiasing = ClientPrefs.data.antialiasing;
		magenta.scrollFactor.set(0, yScroll);
		magenta.setGraphicSize(Std.int(magenta.width * 1.175));
		magenta.updateHitbox();
		magenta.screenCenter();
		magenta.visible = false;
		add(magenta);

		// Decoration sprites that go behind the menu items
		for (d in decorations)
			if (!getBool(d, 'front', false)) createDecoration(d);

		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		for (num => cfg in mainItemConfigs)
		{
			var autoX:Float = mainX + (num * spacingX);
			var autoY:Float = (num * mainSpacing) + mainY;
			if (mainBalance)
				autoY += (4 - mainItemConfigs.length) * (mainSpacing / 2); // Offsets for when you have anything other than 4 items
			createMenuItem(cfg, autoX, autoY, 'left');
		}

		// Achievements and Options are stacked on the right side by default
		if (leftConfig != null)
			leftItem = createMenuItem(leftConfig, 60, 350, 'right');
		if (rightConfig != null)
			rightItem = createMenuItem(rightConfig, 60, 490, 'right');

		// Slide the menu items in when the state opens (can be turned off in the JSON)
		if (slideInConfig.enabled)
		{
			for (num => item in menuItems.members)
				slideIn(item, num < optionShit.length, num * slideInConfig.stagger);
		}

		// Decoration sprites that go in front of the menu items
		for (d in decorations)
			if (getBool(d, 'front', false)) createDecoration(d);

		var verY:Float = FlxG.height - verBottom;
		if (showPsychVer)
		{
			var psychVer:FlxText = new FlxText(verX, verY, 0, "Psych Engine v" + psychEngineVersion, 12);
			psychVer.scrollFactor.set();
			psychVer.setFormat(Paths.font("vcr.ttf"), verSize, verColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(psychVer);
			verY += verSize + 4;
		}
		if (showFnfVer)
		{
			var fnfVer:FlxText = new FlxText(verX, verY, 0, "Friday Night Funkin' v" + Application.current.meta.get('version'), 12);
			fnfVer.scrollFactor.set();
			fnfVer.setFormat(Paths.font("vcr.ttf"), verSize, verColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(fnfVer);
		}
		changeItem();

		#if ACHIEVEMENTS_ALLOWED
		// Unlocks "Freaky on a Friday Night" achievement if it's a Friday and between 18:00 PM and 23:59 PM
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18)
			Achievements.unlock('friday_night_play');

		#if MODS_ALLOWED
		Achievements.reloadList();
		#end
		#end

		#if CHECK_FOR_UPDATES
		if (showOutdatedWarning && ClientPrefs.data.checkForUpdates && substates.OutdatedSubState.updateVersion != psychEngineVersion) {
			persistentUpdate = false;
			showOutdatedWarning = false;
			openSubState(new substates.OutdatedSubState());
		}
		#end

		FlxG.camera.zoom = camZoom;
		FlxG.camera.follow(camFollow, null, followLerp);
	}

	// ------------------------------------------------------------------
	// JSON loading
	// ------------------------------------------------------------------

	function loadConfig()
	{
		// Looks in mods/<yourmod>/data/mainmenu.json first, then assets/data/mainmenu.json
		var raw:String = Paths.getTextFromFile('data/mainmenu.json');
		json = null;
		if (raw != null)
		{
			try { json = Json.parse(raw); }
			catch (e:Dynamic) { trace('Error parsing data/mainmenu.json: ' + e); }
		}
		if (json == null) json = {};

		// Background
		var bgJ:Dynamic = field(json, 'background');
		bgRandomize = getBool(bgJ, 'randomize', true);
		bgCount = Std.int(getFloat(bgJ, 'count', 15));
		bgFixed = Std.int(getFloat(bgJ, 'fixed', 1));
		bgScale = getFloat(bgJ, 'scale', 1.175);
		bgX = getFloat(bgJ, 'x', -80);
		bgY = getFloat(bgJ, 'y', 0);
		bgImagePrefix = getString(bgJ, 'imagePrefix', 'menuart/menuBG');
		bgAlpha = getFloat(bgJ, 'alpha', 1);
		bgColor = getColor(bgJ, 'color', FlxColor.WHITE);

		// Camera
		var camJ:Dynamic = field(json, 'camera');
		followLerp = getFloat(camJ, 'followLerp', 0.15);
		followSelected = getBool(camJ, 'followSelected', true);
		scrollY = getFloat(camJ, 'scrollY', 0.25);
		camZoom = getFloat(camJ, 'zoom', 1);
		followOffsetY = getFloat(camJ, 'followOffsetY', 0);

		// Main (left side) layout
		var layJ:Dynamic = field(json, 'mainLayout');
		mainX = getFloat(layJ, 'x', 60);
		mainY = getFloat(layJ, 'y', 90);
		mainSpacing = getFloat(layJ, 'spacing', 140);
		mainBalance = getBool(layJ, 'balance', true);
		mainScale = getFloat(layJ, 'scale', 1);
		spacingX = getFloat(layJ, 'spacingX', 0); // use this for a horizontal / diagonal menu

		// Main items (each entry can be a plain string or an object with x / y / scale / etc.)
		optionShit = [];
		mainItemConfigs = [];
		var mainJ:Dynamic = field(json, 'mainItems');
		if (mainJ != null && Std.isOfType(mainJ, Array))
		{
			for (entry in cast(mainJ, Array<Dynamic>))
			{
				var cfg:MenuItemConfig = parseItem(entry, null, 'left');
				if (cfg != null && cfg.enabled)
				{
					if (cfg.scale == 0) cfg.scale = mainScale;
					mainItemConfigs.push(cfg);
					optionShit.push(cfg.name);
				}
			}
		}
		if (mainItemConfigs.length < 1)
		{
			for (n in ['story_mode', 'freeplay'])
			{
				var c:MenuItemConfig = parseItem(n, null, 'left');
				c.scale = mainScale;
				mainItemConfigs.push(c);
				optionShit.push(n);
			}
		}

		// Side items
		#if ACHIEVEMENTS_ALLOWED
		var defLeft:String = 'achievements';
		#else
		var defLeft:String = null;
		#end
		leftConfig = parseItem(field(json, 'leftItem'), defLeft, 'right');
		rightConfig = parseItem(field(json, 'rightItem'), 'options', 'right');
		if (leftConfig != null && !leftConfig.enabled) leftConfig = null;
		if (rightConfig != null && !rightConfig.enabled) rightConfig = null;
		leftOption = leftConfig != null ? leftConfig.name : null;
		rightOption = rightConfig != null ? rightConfig.name : null;

		// Slides
		slideInConfig = parseSlide(field(json, 'slideIn'), 0.6, 0.08, 'expoOut');
		slideOutConfig = parseSlide(field(json, 'slideOut'), 0.5, 0.04, 'expoIn');

		// Selected / unselected look
		var selJ:Dynamic = field(json, 'selection');
		selScale = getFloat(selJ, 'selectedScale', 1);
		selAlpha = getFloat(selJ, 'selectedAlpha', 1);
		unselAlpha = getFloat(selJ, 'unselectedAlpha', 1);
		selTween = getFloat(selJ, 'tweenDuration', 0);
		wrapSelection = getBool(selJ, 'wrap', true);

		// Confirm behaviour
		var conJ:Dynamic = field(json, 'confirm');
		flickerEnabled = getBool(conJ, 'flicker', true);
		flickerDuration = getFloat(conJ, 'flickerDuration', 1);
		flickerInterval = getFloat(conJ, 'flickerInterval', 0.06);
		flashEnabled = getBool(conJ, 'flash', true);
		flashDuration = getFloat(conJ, 'flashDuration', 1.1);
		flashInterval = getFloat(conJ, 'flashInterval', 0.15);
		flashColor = getColor(conJ, 'flashColor', FlxColor.WHITE);
		fadeOthers = getBool(conJ, 'fadeOthers', false);
		fadeDuration = getFloat(conJ, 'fadeDuration', 0.4);

		// Sounds
		var sndJ:Dynamic = field(json, 'sounds');
		sndScroll = getString(sndJ, 'scroll', 'scrollMenu');
		sndConfirm = getString(sndJ, 'confirm', 'confirmMenu');
		sndCancel = getString(sndJ, 'cancel', 'cancelMenu');

		allowMouse = getBool(json, 'allowMouse', true);

		// Version text
		var verJ:Dynamic = field(json, 'versionText');
		var verVisible:Bool = getBool(verJ, 'visible', true);
		showPsychVer = verVisible && getBool(verJ, 'showPsych', true);
		showFnfVer = verVisible && getBool(verJ, 'showFnf', true);
		verX = getFloat(verJ, 'x', 12);
		verBottom = getFloat(verJ, 'bottom', 44);
		verSize = Std.int(getFloat(verJ, 'size', 16));
		verColor = getColor(verJ, 'color', FlxColor.WHITE);

		// Decoration sprites
		decorations = [];
		var decJ:Dynamic = field(json, 'sprites');
		if (decJ != null && Std.isOfType(decJ, Array))
			for (d in cast(decJ, Array<Dynamic>))
				decorations.push(d);
	}

	function parseItem(d:Dynamic, defaultName:String, defaultAnchor:String):MenuItemConfig
	{
		var cfg:MenuItemConfig = {
			name: defaultName,
			enabled: true,
			x: null,
			y: null,
			offsetX: 0,
			offsetY: 0,
			scale: 0, // 0 = not set (main items use mainLayout.scale, side items use 1)
			anchor: defaultAnchor,
			angle: 0,
			flipX: false,
			flipY: false,
			color: null,
			antialiasing: null,
			fps: 0,
			image: null,
			idleAnim: null,
			selectedAnim: null,
			state: null,
			url: null
		};

		if (d == null)
			return defaultName != null ? cfg : null;

		if (Std.isOfType(d, String))
		{
			cfg.name = cast d;
			return cfg;
		}

		cfg.name = getString(d, 'name', defaultName);
		cfg.enabled = getBool(d, 'enabled', true);
		cfg.x = hasField(d, 'x') ? getFloat(d, 'x', 0) : null;
		cfg.y = hasField(d, 'y') ? getFloat(d, 'y', 0) : null;
		cfg.offsetX = getFloat(d, 'offsetX', 0);
		cfg.offsetY = getFloat(d, 'offsetY', 0);
		cfg.scale = getFloat(d, 'scale', 0); // 0 = "not set", main items then fall back to mainLayout.scale
		cfg.anchor = getString(d, 'anchor', defaultAnchor);
		cfg.angle = getFloat(d, 'angle', 0);
		cfg.flipX = getBool(d, 'flipX', false);
		cfg.flipY = getBool(d, 'flipY', false);
		cfg.color = getString(d, 'color', null);
		cfg.antialiasing = hasField(d, 'antialiasing') ? getBool(d, 'antialiasing', true) : null;
		cfg.fps = getFloat(d, 'fps', 0);
		cfg.image = getString(d, 'image', null);
		cfg.idleAnim = getString(d, 'idleAnim', null);
		cfg.selectedAnim = getString(d, 'selectedAnim', null);
		cfg.state = getString(d, 'state', null);
		cfg.url = getString(d, 'url', null);
		if (cfg.name == null) return null;
		if (cfg.state != null) customStates.set(cfg.name, cfg.state);
		if (cfg.url != null) customUrls.set(cfg.name, cfg.url);
		return cfg;
	}

	function parseSlide(d:Dynamic, duration:Float, stagger:Float, ease:String):SlideConfig
	{
		return {
			enabled: getBool(d, 'enabled', true),
			duration: getFloat(d, 'duration', duration),
			stagger: getFloat(d, 'stagger', stagger),
			ease: getString(d, 'ease', ease),
			direction: getString(d, 'direction', 'auto')
		};
	}

	// Small helpers so missing / wrong JSON fields never crash the menu
	static function hasField(o:Dynamic, key:String):Bool
		return o != null && Reflect.hasField(o, key) && Reflect.field(o, key) != null;

	static function field(o:Dynamic, key:String):Dynamic
		return hasField(o, key) ? Reflect.field(o, key) : null;

	static function getFloat(o:Dynamic, key:String, def:Float):Float
	{
		if (!hasField(o, key)) return def;
		var v:Float = Std.parseFloat(Std.string(Reflect.field(o, key)));
		return Math.isNaN(v) ? def : v;
	}

	static function getBool(o:Dynamic, key:String, def:Bool):Bool
	{
		if (!hasField(o, key)) return def;
		return Reflect.field(o, key) == true;
	}

	static function getString(o:Dynamic, key:String, def:String):String
		return hasField(o, key) ? Std.string(Reflect.field(o, key)) : def;

	static function getColor(o:Dynamic, key:String, def:FlxColor):FlxColor
	{
		if (!hasField(o, key)) return def;
		return parseColor(Std.string(Reflect.field(o, key)), def);
	}

	static function parseColor(str:String, def:FlxColor):FlxColor
	{
		if (str == null) return def;
		var c:Null<FlxColor> = FlxColor.fromString(str);
		if (c == null) c = FlxColor.fromString('#' + str); // allow "FF0000" without the #
		return c != null ? c : def;
	}

	function playSound(key:String)
	{
		if (key != null && key != '') FlxG.sound.play(Paths.sound(key));
	}

	function getEase(name:String, fallback:Float->Float):Float->Float
	{
		var f:Dynamic = Reflect.field(FlxEase, name);
		return (f != null && Reflect.isFunction(f)) ? f : fallback;
	}

	// ------------------------------------------------------------------
	// Menu items
	// ------------------------------------------------------------------

	function createMenuItem(cfg:MenuItemConfig, autoX:Float, autoY:Float, autoAnchor:String):FlxSprite
	{
		var name:String = cfg.name;
		var menuItem:FlxSprite = new FlxSprite();
		var image:String = cfg.image != null ? cfg.image : 'mainmenu/menu_$name';
		var idlePrefix:String = cfg.idleAnim != null ? cfg.idleAnim : '$name idle';
		var selectedPrefix:String = cfg.selectedAnim != null ? cfg.selectedAnim : '$name selected';
		var fps:Float = cfg.fps > 0 ? cfg.fps : 24;
		menuItem.frames = Paths.getSparrowAtlas(image);
		menuItem.animation.addByPrefix('idle', idlePrefix, fps, true);
		menuItem.animation.addByPrefix('selected', selectedPrefix, fps, true);
		menuItem.animation.play('idle');

		// Size
		var scale:Float = cfg.scale > 0 ? cfg.scale : 1;
		menuItem.scale.set(scale, scale);
		menuItem.updateHitbox();

		// Position: x/y from the JSON win, otherwise the automatic layout is used
		var px:Float = cfg.x != null ? cfg.x : autoX;
		var py:Float = cfg.y != null ? cfg.y : autoY;
		var anchor:String = cfg.anchor != null ? cfg.anchor : autoAnchor;
		menuItem.x = (anchor == 'right') ? (FlxG.width - px - menuItem.width) : px;
		menuItem.y = py;
		menuItem.x += cfg.offsetX;
		menuItem.y += cfg.offsetY;

		menuItem.angle = cfg.angle;
		menuItem.flipX = cfg.flipX;
		menuItem.flipY = cfg.flipY;
		if (cfg.color != null) menuItem.color = parseColor(cfg.color, FlxColor.WHITE);
		baseScales.set(menuItem, scale);

		menuItem.antialiasing = cfg.antialiasing != null ? cfg.antialiasing : ClientPrefs.data.antialiasing;
		menuItem.scrollFactor.set();
		menuItems.add(menuItem);
		return menuItem;
	}

	function createDecoration(d:Dynamic)
	{
		var img:String = getString(d, 'image', null);
		if (img == null) return;

		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(img));
		var sc:Float = getFloat(d, 'scale', 1);
		spr.scale.set(sc, sc);
		spr.updateHitbox();

		var px:Float = getFloat(d, 'x', 0);
		var py:Float = getFloat(d, 'y', 0);
		switch (getString(d, 'anchor', 'left'))
		{
			case 'right': spr.x = FlxG.width - px - spr.width;
			case 'center': spr.x = ((FlxG.width - spr.width) / 2) + px;
			default: spr.x = px;
		}
		spr.y = py;

		spr.alpha = getFloat(d, 'alpha', 1);
		spr.angle = getFloat(d, 'angle', 0);
		spr.antialiasing = ClientPrefs.data.antialiasing;
		spr.scrollFactor.set(getFloat(d, 'scrollFactorX', 0), getFloat(d, 'scrollFactorY', 0));
		add(spr);
	}

	// Applies the selected / unselected scale and alpha to an item
	function setItemState(item:FlxSprite, selected:Bool)
	{
		var base:Float = baseScales.exists(item) ? baseScales.get(item) : 1;
		var targetScale:Float = base * (selected ? selScale : 1);
		var targetAlpha:Float = selected ? selAlpha : unselAlpha;

		FlxTween.cancelTweensOf(item.scale);
		FlxTween.cancelTweensOf(item, ['alpha']);
		if (selTween > 0)
		{
			FlxTween.tween(item.scale, {x: targetScale, y: targetScale}, selTween, {ease: FlxEase.quadOut});
			FlxTween.tween(item, {alpha: targetAlpha}, selTween, {ease: FlxEase.quadOut});
		}
		else
		{
			item.scale.set(targetScale, targetScale);
			item.alpha = targetAlpha;
		}
	}

	// What happens after the confirm flicker
	function openOption(option:String, item:FlxSprite)
	{
		// Items with their own "state" / "url" in the JSON
		var stateName:String = customStates.get(option);
		if (stateName != null)
		{
			var cls:Class<Dynamic> = Type.resolveClass(stateName);
			if (cls != null)
			{
				MusicBeatState.switchState(cast Type.createInstance(cls, []));
				return;
			}
			trace('Menu Item ${option}: couldn\'t find state "$stateName"');
			selectedSomethin = false;
			item.visible = true;
			return;
		}
		var link:String = customUrls.get(option);
		if (link != null)
		{
			CoolUtil.browserLoad(link);
			selectedSomethin = false;
			item.visible = true;
			return;
		}

		switch (option)
		{
			case 'story_mode':
				MusicBeatState.switchState(new StoryMenuState());
			case 'freeplay':
				MusicBeatState.switchState(new FreeplayState());

			#if MODS_ALLOWED
			case 'mods':
				MusicBeatState.switchState(new ModsMenuState());
			#end

			#if ACHIEVEMENTS_ALLOWED
			case 'achievements':
				MusicBeatState.switchState(new AchievementsMenuState());
			#end

			case 'credits':
				MusicBeatState.switchState(new CreditsState());
			case 'options':
				MusicBeatState.switchState(new OptionsState());
				OptionsState.onPlayState = false;
				if (PlayState.SONG != null)
				{
					PlayState.SONG.arrowSkin = null;
					PlayState.SONG.splashSkin = null;
					PlayState.stageUI = 'normal';
				}
			case 'donate':
				CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
				selectedSomethin = false;
				item.visible = true;
			default:
				trace('Menu Item ${option} doesn\'t do anything');
				selectedSomethin = false;
				item.visible = true;
		}
	}

	function slideIn(item:FlxSprite, isMain:Bool, delay:Float = 0)
	{
		var dir:String = slideInConfig.direction;
		if (dir == 'auto') dir = isMain ? 'left' : 'right'; // main items come from the left, side buttons from the right

		var ease = getEase(slideInConfig.ease, FlxEase.expoOut);
		switch (dir)
		{
			case 'up':
				var targetY:Float = item.y;
				item.y = -item.height - 20;
				FlxTween.tween(item, {y: targetY}, slideInConfig.duration, {ease: ease, startDelay: delay});
			case 'down':
				var targetY:Float = item.y;
				item.y = FlxG.height + 20;
				FlxTween.tween(item, {y: targetY}, slideInConfig.duration, {ease: ease, startDelay: delay});
			case 'right':
				var targetX:Float = item.x;
				item.x = FlxG.width + 20;
				FlxTween.tween(item, {x: targetX}, slideInConfig.duration, {ease: ease, startDelay: delay});
			default: // left
				var targetX:Float = item.x;
				item.x = -item.width - 20;
				FlxTween.tween(item, {x: targetX}, slideInConfig.duration, {ease: ease, startDelay: delay});
		}
	}

	function slideOut(item:FlxSprite, isMain:Bool, delay:Float = 0)
	{
		var dir:String = slideOutConfig.direction;
		if (dir == 'auto') dir = isMain ? 'left' : 'right';

		var ease = getEase(slideOutConfig.ease, FlxEase.expoIn);
		switch (dir)
		{
			case 'up':
				FlxTween.tween(item, {y: -item.height - 20}, slideOutConfig.duration, {ease: ease, startDelay: delay});
			case 'down':
				FlxTween.tween(item, {y: FlxG.height + 20}, slideOutConfig.duration, {ease: ease, startDelay: delay});
			case 'right':
				FlxTween.tween(item, {x: FlxG.width + 20}, slideOutConfig.duration, {ease: ease, startDelay: delay});
			default: // left
				FlxTween.tween(item, {x: -item.width - 20}, slideOutConfig.duration, {ease: ease, startDelay: delay});
		}
	}

	var selectedSomethin:Bool = false;

	var timeNotMoving:Float = 0;
	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.8)
			FlxG.sound.music.volume = Math.min(FlxG.sound.music.volume + 0.5 * elapsed, 0.8);

		if (!selectedSomethin)
		{
			if (controls.UI_UP_P)
			{
				if (curColumn == RIGHT && leftOption != null)
				{
					curColumn = LEFT; // Options -> Achievements (up)
					changeItem();
				}
				else if (curColumn == CENTER)
					changeItem(-1);
			}

			if (controls.UI_DOWN_P)
			{
				if (curColumn == LEFT && rightOption != null)
				{
					curColumn = RIGHT; // Achievements -> Options (down)
					changeItem();
				}
				else if (curColumn == CENTER)
					changeItem(1);
			}

			var allowMouse:Bool = allowMouse;
			if (allowMouse && ((FlxG.mouse.deltaScreenX != 0 && FlxG.mouse.deltaScreenY != 0) || FlxG.mouse.justPressed)) //FlxG.mouse.deltaScreenX/Y checks is more accurate than FlxG.mouse.justMoved
			{
				allowMouse = false;
				FlxG.mouse.visible = true;
				timeNotMoving = 0;

				var selectedItem:FlxSprite;
				switch(curColumn)
				{
					case CENTER:
						selectedItem = menuItems.members[curSelected];
					case LEFT:
						selectedItem = leftItem;
					case RIGHT:
						selectedItem = rightItem;
				}

				if(leftItem != null && FlxG.mouse.overlaps(leftItem))
				{
					allowMouse = true;
					if(selectedItem != leftItem)
					{
						curColumn = LEFT;
						changeItem();
					}
				}
				else if(rightItem != null && FlxG.mouse.overlaps(rightItem))
				{
					allowMouse = true;
					if(selectedItem != rightItem)
					{
						curColumn = RIGHT;
						changeItem();
					}
				}
				else
				{
					var dist:Float = -1;
					var distItem:Int = -1;
					for (i in 0...optionShit.length)
					{
						var memb:FlxSprite = menuItems.members[i];
						if(FlxG.mouse.overlaps(memb))
						{
							var distance:Float = Math.sqrt(Math.pow(memb.getGraphicMidpoint().x - FlxG.mouse.screenX, 2) + Math.pow(memb.getGraphicMidpoint().y - FlxG.mouse.screenY, 2));
							if (dist < 0 || distance < dist)
							{
								dist = distance;
								distItem = i;
								allowMouse = true;
							}
						}
					}

					if(distItem != -1 && selectedItem != menuItems.members[distItem])
					{
						curColumn = CENTER;
						curSelected = distItem;
						changeItem();
					}
				}
			}
			else
			{
				timeNotMoving += elapsed;
				if(timeNotMoving > 2) FlxG.mouse.visible = false;
			}

			switch(curColumn)
			{
				case CENTER:
					// The side buttons are on the right now, so press RIGHT to reach them
					if(controls.UI_RIGHT_P)
					{
						if(leftOption != null)
						{
							curColumn = LEFT; // Achievements (top right)
							changeItem();
						}
						else if(rightOption != null)
						{
							curColumn = RIGHT; // Options (bottom right)
							changeItem();
						}
					}

				case LEFT:
					if(controls.UI_LEFT_P)
					{
						curColumn = CENTER;
						changeItem();
					}

				case RIGHT:
					if(controls.UI_LEFT_P)
					{
						curColumn = CENTER;
						changeItem();
					}
			}

			if (controls.BACK)
			{
				selectedSomethin = true;
				FlxG.mouse.visible = false;
				playSound(sndCancel);
				MusicBeatState.switchState(new TitleState());
			}

			if (controls.ACCEPT || (FlxG.mouse.justPressed && allowMouse))
			{
				playSound(sndConfirm);
				selectedSomethin = true;
				FlxG.mouse.visible = false;

				if (flashEnabled && ClientPrefs.data.flashing)
				{
					magenta.color = flashColor;
					FlxFlicker.flicker(magenta, flashDuration, flashInterval, false);
				}

				var item:FlxSprite;
				var option:String;
				switch(curColumn)
				{
					case CENTER:
						option = optionShit[curSelected];
						item = menuItems.members[curSelected];

					case LEFT:
						option = leftOption;
						item = leftItem;

					case RIGHT:
						option = rightOption;
						item = rightItem;
				}

				if (flickerEnabled)
					FlxFlicker.flicker(item, flickerDuration, flickerInterval, false, false, function(flick:FlxFlicker) openOption(option, item));
				else
					openOption(option, item);

				// Fade the other items out
				if (fadeOthers)
				{
					for (memb in menuItems.members)
					{
						if (memb == item) continue;
						FlxTween.cancelTweensOf(memb, ['alpha']);
						FlxTween.tween(memb, {alpha: 0}, fadeDuration);
					}
				}

				// Slide the other items out (can be turned off in the JSON)
				if (slideOutConfig.enabled)
				{
					for (num => memb in menuItems.members)
					{
						if(memb == item)
							continue;

						slideOut(memb, num < optionShit.length, (num * slideOutConfig.stagger));
					}
				}
			}
			#if desktop
			if (controls.justPressed('debug_1'))
			{
				selectedSomethin = true;
				FlxG.mouse.visible = false;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
			#end
		}

		super.update(elapsed);
	}

	function changeItem(change:Int = 0)
	{
		if(change != 0) curColumn = CENTER;
		var next:Int = curSelected + change;
		curSelected = wrapSelection ? FlxMath.wrap(next, 0, optionShit.length - 1) : Std.int(FlxMath.bound(next, 0, optionShit.length - 1));
		playSound(sndScroll);

		for (item in menuItems)
		{
			item.animation.play('idle');
			item.centerOffsets();
			setItemState(item, false);
		}

		var selectedItem:FlxSprite;
		switch(curColumn)
		{
			case CENTER:
				selectedItem = menuItems.members[curSelected];
			case LEFT:
				selectedItem = leftItem;
			case RIGHT:
				selectedItem = rightItem;
		}
		selectedItem.animation.play('selected');
		selectedItem.centerOffsets();
		setItemState(selectedItem, true);
		if (followSelected)
			camFollow.y = selectedItem.getGraphicMidpoint().y + followOffsetY;
	}
}
