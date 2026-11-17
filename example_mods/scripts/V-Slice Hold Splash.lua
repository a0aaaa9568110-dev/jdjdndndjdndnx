colors = {'Purple','Blue','Green','Red'}
sigmacheck=getPropertyFromClass('states.PlayState', 'isPixelStage')
path = sigmacheck and 'holdCover/hcrgbp' or 'holdCover/hcrgb'
function createSprite(c,su)
wawa = 'hold'..c..su
makeAnimatedLuaSprite(wawa,path)
addAnimationByPrefix(wawa,'hold','lop',sigmacheck and 33 or 24,true)
addAnimationByPrefix(wawa,'end','bai',sigmacheck and 33 or 24,false)
addLuaSprite(wawa,true)
setProperty(wawa..'.visible', false)
setObjectCamera(wawa,'hud')

if sigmacheck then
scaleObject(wawa,6,6)
setProperty(wawa..'.antialiasing', false)
end
end

function onCountdownStarted()
for i,color in pairs(colors) do
createSprite(color,'BF')
createSprite(color,'DAD')
end

for _,suffix in pairs({'BF','DAD'}) do
for j,color in pairs(colors) do
wawa='hold'..color..suffix
idx=suffix=='DAD'and j-1 or j+3
createInstance('rgb_'..wawa,'shaders.RGBPalette')
s='strumLineNotes.members['..idx..'].rgbShader.'
for _,c in pairs({'r','g','b'}) do
setProperty('rgb_'..wawa..'.'..c,getProperty(s..c))
end
setProperty(wawa..'.shader',instanceArg('rgb_'..wawa..'.shader'),false,true)
end
end
end

function goodNoteHit(i,d,_,s)
noteHit(false,i,d,s)
end

function opponentNoteHit(i,d,_,s)
noteHit(true,i,d,s)
end

function onKeyRelease(n)
setProperty('hold'..colors[n+1]..'BF.visible', false)
end

function onResume()
for i = 1, #colors do
setProperty('hold'..colors[i]..'BF.visible', false)
end
end

function noteHit(op,i,d,s)
if not s then return end
wawa = 'hold' .. colors[d+1] .. (op and 'DAD' or 'BF')
isEnd = stringEndsWith(getPropertyFromGroup('notes', i, 'animation.name'), 'end')
setProperty(wawa .. '.visible', not (op and isEnd))
playAnim(wawa,not op and isEnd and 'end' or 'hold')
end

function onUpdatePost()
for i, color in pairs(colors) do
for j, suffix in pairs({'BF','DAD'}) do
wawa='hold'..color..suffix
if suffix == 'BF' and getProperty(wawa..'.animation.name')=='end' and getProperty(wawa..'.animation.finished') then
setProperty(wawa..'.visible', false)
playAnim(wawa, 'hold')
end

if getProperty(wawa..'.animation.name')=='end' then
setProperty(wawa..'.visible',true)
end

strumIndex = suffix == 'BF' and i+3 or i-1
posx, posy = getProperty('strumLineNotes.members['..strumIndex..'].x'), getProperty('strumLineNotes.members['..strumIndex..'].y')
if sigmacheck then
callMethod(wawa..'.setPosition', {posx-385, posy - 125})
else
callMethod(wawa..'.setPosition', {posx-105,posy-100})
end
setProperty(wawa..'.alpha', getProperty('strumLineNotes.members['..strumIndex..'].alpha'))
end
end
end