-- WordHelper self-contained launcher
-- Saves this exact version locally so server-browser teleports reload it.

local WORDHELPER_FILE = "WordHelper_Current.lua"
local WORDHELPER_SOURCE = [=[
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

local cloneref = cloneref or function(o) return o end
local gethui = gethui or function() return CoreGui end

local CoreGui = cloneref(game:GetService("CoreGui"))
local Players = cloneref(game:GetService("Players"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))

local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local TOGGLE_KEY = Enum.KeyCode.RightControl
local MIN_CPM = 50
local MAX_CPM_LEGIT = 1500
local MAX_CPM_BLATANT = 3000

math.randomseed(os.time())

local THEME = {
    Background = Color3.fromRGB(20, 20, 24),
    ItemBG = Color3.fromRGB(32, 32, 38),
    Accent = Color3.fromRGB(114, 100, 255),
    Text = Color3.fromRGB(240, 240, 240),
    SubText = Color3.fromRGB(150, 150, 160),
    Success = Color3.fromRGB(100, 255, 140),
    Warning = Color3.fromRGB(255, 200, 80),
    Slider = Color3.fromRGB(60, 60, 70)
}

local function ColorToRGB(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local ConfigFile = "WordHelper_Config.json"
local Config = {
    CPM = 550,
    Blatant = false,
    Humanize = true,
    FingerModel = true,
    SortMode = "Random",
    SuffixMode = "",
    LengthMode = 0,
    AutoPlay = false,
    AutoJoin = false,
    AutoJoinSettings = {
        _1v1 = true,
        _4p = true,
        _8p = true
    },
    PanicMode = true,
    ShowKeyboard = false,
    ErrorRate = 5,
    ThinkDelay = 0.8,
    RiskyMistakes = false,
    CustomWords = {},
    MinTypeSpeed = 50,
    MaxTypeSpeed = 3000,
    KeyboardLayout = "QWERTY",
    ShowUsedWords = false,
    GodmodePriority = {
        "__TRAP__",
        "ler",
        "ines",
        "ters",
        "ting",
        "ally",
        "ely",
        "king",
        "pers",
        "__X__"
    }
}


Config.SortMode = "Unbeatable" -- Defaulted to your new mode

-- Tracker state specifically for your Unbeatable strategy calculation
local UnbeatableTracker = {
    TotalTurnsPlayed = 0,
    CurrentTargetPrefixLength = 2 -- Starts giving opponent 2 letters (from 3 letter words), scales up to 4
}

local function SaveConfig()

    if writefile then
        writefile(ConfigFile, HttpService:JSONEncode(Config))
    end
end

local function LoadConfig()
    if isfile and isfile(ConfigFile) then
        local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(ConfigFile)) end)
        if success and decoded then
            for k, v in pairs(decoded) do Config[k] = v end
        end
    end
end
LoadConfig()

-- ============================================================
-- 476,666-word dictionary migration: ONE-TIME clean slate
-- Clears the old learned/discovered-word pool and rejected-word blacklist
-- only the first time this build is launched. Later teleports/reloads keep
-- any NEW discoveries/rejections collected while testing this build.
-- Custom trap words are intentionally preserved.
-- ============================================================
local CLEAN_SLATE_MARKER = "WordHelper_476666_CleanSlate.done"
if not (isfile and isfile(CLEAN_SLATE_MARKER)) then
    Config.CustomWords = {}

    if writefile then
        pcall(function()
            writefile("WordHelper_RejectedWords.json", "[]")
        end)
        pcall(function()
            writefile(
                "WordHelper_DiscoveredWords.json",
                HttpService:JSONEncode({pending = {}, ignored = {}})
            )
        end)
    end

    SaveConfig()

    if writefile then
        pcall(function()
            writefile(CLEAN_SLATE_MARKER, "476666")
        end)
    end
end

local currentCPM = Config.CPM
local isBlatant = Config.Blatant
local useHumanization = Config.Humanize
local useFingerModel = Config.FingerModel
local sortMode = Config.SortMode
if sortMode == "Killer" then
    sortMode = "Godmode"
    Config.SortMode = "Godmode"
end
local suffixMode = Config.SuffixMode or ""
local lengthMode = Config.LengthMode or 0
local autoPlay = Config.AutoPlay
local autoJoin = Config.AutoJoin
local panicMode = Config.PanicMode
local showKeyboard = Config.ShowKeyboard
local errorRate = Config.ErrorRate
local thinkDelayCurrent = Config.ThinkDelay
local riskyMistakes = Config.RiskyMistakes
local keyboardLayout = Config.KeyboardLayout or "QWERTY"

local isTyping = false
local isAutoPlayScheduled = false
local lastTypingStart = 0
local runConn = nil
local inputConn = nil
local logConn = nil
local unloaded = false
local isMyTurnLogDetected = false
local logRequiredLetters = ""
local turnExpiryTime = 0
local Blacklist = {}
local UsedWords = {}
local RandomOrderCache = {}
local RandomPriority = {}
local lastDetected = "---"
local lastLogicUpdate = 0
local lastAutoJoinCheck = 0
local lastWordCheck = 0
local cachedDetected = ""
local cachedCensored = false
local LOGIC_RATE = 0.1
local AUTO_JOIN_RATE = 0.5
local UpdateList
local ButtonCache = {}
local ButtonData = {}
local JoinDebounce = {}
local thinkDelayMin = 0.4
local thinkDelayMax = 1.2

local listUpdatePending = false
local forceUpdateList = false
local lastInputTime = 0
local LIST_DEBOUNCE = 0.05
local currentBestMatch = nil

if logConn then logConn:Disconnect() end
logConn = LogService.MessageOut:Connect(function(message, type)
    local wordPart, timePart = message:match("Word:%s*([A-Za-z]+)%s+Time to respond:%s*(%d+)")
    if wordPart and timePart then
        isMyTurnLogDetected = true
        logRequiredLetters = wordPart
        turnExpiryTime = tick() + tonumber(timePart)
    end
end)

-- ============================================================
-- Embedded Last Letter Library master dictionary
-- Exact collector snapshot: 476,666 collected words.
-- This replaces the old remote english-words dictionary entirely.
-- ============================================================
local EmbeddedWordList = [==[
aa
aaah
aaargh
aah
aahing
aahs
aalenian
aalii
aaliis
aani
aardonyx
aardvark
aardvarks
aardwolf
aardwolves
aargh
aarhus
aaron
aaronic
aaronite
aaronites
aarrgh
aarrghh
aarti
aartis
aaru
aas
aasvogel
aasvogels
aatman
aatmans
ab
aba
ababdeh
ababua
abac
abaca
abacas
abacate
abacavir
abacaxi
abacaxis
abaci
abacinate
abacination
abacisci
abaciscus
abacist
abacists
aback
abacot
abacs
abacterial
abactinal
abactinally
abaction
abactor
abactors
abaculi
abaculus
abacus
abacuses
abada
abaddon
abadengo
abadite
abaecin
abaecins
abaft
abagusii
abaisance
abaiser
abaisse
abaka
abakas
abalienate
abalienated
abalienates
abalienating
abalienation
abalienations
abalone
abalones
abaloparatide
abama
abamp
abampere
abamperes
abamps
aband
abanded
abanding
abandon
abandonable
abandoned
abandonedly
abandonee
abandonees
abandoner
abandoners
abandoning
abandonment
abandonments
abandons
abandonware
abandonwares
abands
abanet
abanic
abantes
abapical
abaptiston
abaris
abarthrosis
abarticular
abarticulation
abas
abase
abased
abasedly
abasedness
abasement
abasements
abaser
abasers
abases
abasgi
abash
abashed
abashedly
abashedness
abashes
abashing
abashless
abashlessly
abashment
abashments
abasia
abasias
abasic
abasing
abask
abassi
abastard
abastardize
abatable
abatacept
abatage
abate
abated
abatement
abatements
abater
abaters
abates
abatic
abating
abatis
abatised
abatises
abatjour
abatjours
abaton
abator
abators
abattage
abattis
abattised
abattises
abattoir
abattoirs
abattu
abature
abatures
abaxial
abaxile
abay
abaya
abayah
abayas
abaze
abb
abba
abbacies
abbacy
abbandono
abbas
abbasi
abbasid
abbassi
abbate
abbatial
abbatical
abbatie
abbaye
abbe
abbed
abbes
abbess
abbesses
abbevillian
abbey
abbeys
abbeystead
abbeystede
abbie
abboccato
abbot
abbotcies
abbotcy
abbotnullius
abbotric
abbots
abbotship
abbotships
abbott
abbozzi
abbozzo
abbr
abbrev
abbreviatable
abbreviate
abbreviated
abbreviately
abbreviates
abbreviating
abventions
abbreviator
abbreviators
abbreviatory
abbreviature
abbreviatures
abbs
abby
abc
abcee
abcees
abciximab
abcoulomb
abcoulombs
abdabs
abdal
abdat
abderian
abderite
abdest
abdicable
abdicant
abdicants
abdicate
abdicated
abdicates
abdicating
abdication
abdications
abdicative
abdicator
abdicators
abdiel
abditive
abditory
abdom
abdomen
abdomens
abdomina
abdominal
abdominalia
abdominalian
abdominally
abdominals
abdominocardiac
abdominocenteses
abdominocentesis
abdominocystic
abdominogenital
abdominohysterectomy
abdominohysterotomy
abdominoplasties
abdominoplasty
abdominoscope
abdominoscopy
abdominothoracic
abdominous
abdominovaginal
abdominovesical
abduce
abduced
abducens
abducent
abducentes
abduces
abducing
abduct
abducted
abductee
abductees
abducting
abobation
abductions
abductor
abductores
abductors
abducts
abe
abeam
abear
abearance
abearing
abears
abecedaria
abecedarian
abecedarians
abecedaries
abecedarium
abecedarius
abecedary
abed
abegge
abegging
abeigh
abel
abelacimab
abele
abeles
abelia
abelian
abelias
abelisaurus
abelisauruses
abelite
abellaite
abellaites
abelmoschus
abelmosk
abelmosks
abelmusk
abelonian
abelsonite
abelsonites
abeltree
abemaciclib
abencerrages
abend
abendmusik
abendmusiken
abends
abenteric
aber
aberdavine
aberdeen
aberdevine
aberdevines
aberdonian
aberduvine
aberia
abernathyite
abernathyites
abernethies
abernethy
aberr
aberrance
aberrances
aberrancies
aberrancy
aberrant
aberrantly
aberrants
aberrate
aberrated
aberrates
aberrating
aberration
aberrational
aberrations
aberrative
aberrator
aberrometer
aberroscope
abers
aberuncate
aberuncator
abessive
abessives
abet
abetalipoproteinaemia
abetalipoproteinaemias
abetalipoproteinemia
abetalipoproteinemias
abetment
abetments
abets
abettal
abettals
abetted
abetter
abetters
abetting
abettor
abettors
abey
abeyance
abeyances
abeyancies
abeyancy
abeyant
abfarad
abfarads
abhenries
abhenry
abhenrys
abhinaya
abhiseka
abhominable
abhor
abhorred
abhorrence
abhorrences
abhorrencies
abhorrency
abhorrent
abhorrently
abhorrer
abhorrers
abhorrible
abhorring
abhorrings
abhors
abhorson
abhurite
abhurites
abhyanga
abhyangas
abib
abibliophobia
abid
abidal
abidance
abidances
abidden
abide
abided
abider
abiders
abides
abidi
abiding
abidingly
abidingness
abidings
abie
abience
abient
abies
abietate
abietene
abietes
abietic
abietin
abietineous
abietinic
abietite
abiezer
abigail
abgails
abigailship
abigeat
abigei
abigeus
abilao
abilene
abiliment
abilities
ability
abilla
abilo
abime
abiogeneses
abiogenesis
abiogenesist
abiogenetic
abiogenetical
abiogenetically
abiogenic
abiogenically
abiogenist
abiogenists
abiogenous
abiogeny
abiological
abiologically
abiology
abioses
abiosis
abiotic
abiotically
abiotrophic
abiotrophies
abiotrophy
abipon
abir
abiraterone
abirritant
abirritants
abirritate
abirritated
abirritates
abirritating
abirritation
abirritative
abit
abitibi
abitur
abiturient
abiturients
abiturs
abiu
abiuret
abius
abjad
abjads
abject
abjected
abjectedness
abjecting
abjection
abjections
abjective
abjectly
abjectness
abjectnesses
abjects
abjoint
abjointed
abjointing
abjoints
abjudge
abjudged
abjudging
abjudicate
abjudicated
abjudicating
abjudication
abjugate
abjunct
abjunction
abjunctions
abjunctive
abjuration
abjurations
abjuratory
abjure
abjured
abjurement
abjurer
abjurers
abjures
abjuring
abkar
abkari
abkary
abkhas
abkhasian
abkhaz
abkhazian
abkhazians
abl
ablach
ablactate
ablactated
ablactating
ablactation
ablactations
ablaqueate
ablare
ablastemic
ablastin
ablastous
ablate
ablated
ablates
ablating
ablation
ablations
ablatitious
ablatival
ablative
ablatively
ablatives
ablator
ablators
ablaut
ablauts
ablaze
able
ablebodied
abled
ableeze
ablegate
ablegates
ablegation
ableism
ableisms
ableist
ableists
ableness
ablepharia
ablepharon
ablepharous
ablepharus
ablepsia
ablepsy
ableptical
abler
ables
ablest
ablet
ablets
ablewhackets
abling
ablings
ablins
ablock
abloom
ablow
ablude
abluent
abluents
ablush
ablute
abluted
ablution
ablutionary
ablutions
ablutomane
ablutomanes
ablutophobia
abluvion
ably
abmho
abmhos
abmodality
abn
abnaki
abnegate
abnegated
abnegates
abnegating
abnegation
abnegations
abnegative
abnegator
abnegators
abner
abnerval
abnet
abneural
abnormal
abnormalcies
abnormalcy
abnormalise
abnormalised
abnormalising
abnormalism
abnormalisms
abnormalist
abnormalities
abnormality
abnormalize
abnormalized
abnormalizing
abnormally
abnormalness
abnormals
abnormities
abnormity
abnormous
abnumerable
abo
aboard
abobra
abodah
abode
aboded
abodement
abodements
abodes
aboding
abogado
abogados
abohm
abohms
aboideau
aboideaus
aboideaux
aboil
aboiteau
aboiteaus
aboiteaux
abolish
abolishable
abolished
abolisher
abolishers
abolishes
abolishing
abolishment
abolishments
abolition
abolitional
abolitionary
abolitionise
abolitionised
abolitionising
abolitionism
abolitionisms
abolitionist
abolitionists
abolitionize
abolitionized
abolitionizing
abolitions
abollla
abollae
abollas
aboma
abomas
abomasa
abomasal
abomasi
abomasum
abomasus
abominable
abominableness
abominably
abominate
abominated
abominates
abominating
abomination
abominations
abominator
abominators
abomine
abondance
abondances
abongo
abonnement
abonnements
aboon
aborad
aboral
aborally
abord
aborded
abording
abords
abore
aborigen
aborigens
aborigin
aboriginal
aboriginalism
aboriginalisms
aboriginalities
aboriginality
aboriginally
aboriginals
aboriginary
aborigine
aborigines
aborigins
aborne
aborning
aborsement
aborsive
abort
aborted
abortee
abortees
aborter
aborters
aborticide
aborticides
abortient
abortifacient
abortifacients
abortin
aborting
abortion
abortional
abortionist
abortionists
abortions
abortive
abortively
abortiveness
abortivenesses
abortogenic
aborts
abortuaries
abortuary
abortus
abortuses
abos
abouchement
aboudikro
abought
aboulia
aboulias
aboulic
abound
abounded
abounder
abounding
aboundingly
abounds
about
abouts
above
aboveboard
abovedeck
aboveground
abovementioned
aboveproof
aboves
abovesaid
abovestairs
abow
abox
abozzi
abozzo
abp
abr
abracadabra
abracadabras
abrachia
abrachias
abradable
abradant
abradants
abrade
abraded
abrader
abraders
abrades
abrading
abraham
abrahamic
abrahamite
abrahamitic
abraid
abraided
abraiding
abraids
abram
abramis
abranchial
abranchialism
abranchialisms
abranchiata
abranchiate
abranchious
abrasax
abrasaxes
abrase
abrased
abraser
abrash
abrasing
abrasiometer
abrasion
abrasions
abrasive
abrasively
abrasiveness
abrasivenesses
abrasives
abrastol
abraum
abraxas
abraxases
abray
abrayed
abraying
abrays
abrazo
abrazos
abreact
abreacted
abreacting
abreaction
abreactions
abreactive
abreacts
abreast
abreed
abrege
abreges
abreid
abrenounce
abrenunciation
abreption
abreuvoir
abri
abricock
abricocks
abricot
abrictosaurus
abrictosauruses
abridgable
abridge
abridgeable
abridged
abridgedly
abridgement
abridgements
abridger
abridgers
abridges
abridging
abridgment
abridgments
abrim
abrin
abrine
abrins
abris
abristle
abroach
abroad
abroads
abrocitinib
abrocoma
abrocome
abrogable
abrogate
abrogated
abrogates
abrogating
abrogation
abrogations
abrogative
abrogator
abrogators
abroma
abronia
abrood
abrook
abrooke
abrooked
abrookes
abrooking
abrosaurus
abrosauruses
abrosexual
abrosexualism
abrosexualisms
abrosexualities
abrosexuality
abrosia
abrosias
abrotanum
abrotanums
abrotine
abrupt
abruptedly
abrupter
abruptest
abruptio
abruption
abruptions
abruptly
abruptness
abruptnesses
abrupts
abrus
abs
absalom
absampere
absaroka
absarokite
abscam
abscess
abscessed
abscesses
abscessing
abscession
abscessroot
abscind
abscinded
abscinding
abscinds
abscise
abscised
abscises
abscisic
abscisin
abscising
abscisins
abscision
absciss
abscissa
abscissae
abscissas
abscisse
abscisses
abscissin
abscissins
abscission
abscissions
absconce
abscond
absconded
abscondence
abscondences
absconder
absconders
absconding
abscondings
absconds
absconsa
abseil
abseiled
abseiler
abseilers
abseiling
abseilings
abseils
absence
absences
absent
absentation
absented
absentee
absenteeism
absenteeisms
absentees
absenteeship
absenter
absenters
absentia
absenting
absently
absentment
absentminded
absentmindedly
absentmindedness
absentmindednesses
absentness
absents
absey
abseys
absi
absinth
absinthe
absinthes
absinthial
absinthian
absinthiate
absinthiated
absinthiating
absinthic
absinthiin
absinthin
absinthine
absinthism
absinthismic
absinthisms
absinthium
absinthol
absinths
absis
absist
absit
absits
absohm
absolute
absolutely
absoluteness
absolutenesses
absoluter
fifths
asialoorosomucoid
asialoorosomucoids
zanza
nzani
nzanza
nzazas
]==]

local Dictionary = {}
local WordIndexer = {}
for word in string.gmatch(EmbeddedWordList, "%s*([%a]+)%s*") do
    local lowerWord = string.lower(word)
    if not WordIndexer[lowerWord] then
        table.insert(Dictionary, lowerWord)
        WordIndexer[lowerWord] = true
    end
end


-- Fast lookahead helper to verify opponent options
local function CountValidReturnsForSuffix(suffix)
    local count = 0
    for _, dictWord in ipairs(Dictionary) do
        if string.sub(dictWord, 1, #suffix) == suffix then
            count = count + 1
            if count >= 3 then return count end -- Performance exit once threshold met
        end
    end
    return count
end

-- Core processing logic for Unbeatable sorting mode
local function GetUnbeatableWord(requiredPrefix)
    requiredPrefix = string.lower(requiredPrefix)
    
    -- 1. Track stage lengths based on turn intervals
    UnbeatableTracker.TotalTurnsPlayed = UnbeatableTracker.TotalTurnsPlayed + 1
    local calculatedTarget = 2 + math.floor((UnbeatableTracker.TotalTurnsPlayed - 1) / 5)
    if calculatedTarget > 4 then calculatedTarget = 4 end
    UnbeatableTracker.CurrentTargetPrefixLength = calculatedTarget

    local candidates = {}
    
    -- 2. Scan memory pool for valid prefixes
    for _, word in ipairs(Dictionary) do
        if string.sub(word, 1, #requiredPrefix) == requiredPrefix and #word > #requiredPrefix then
            if not UsedWords[word] and not Blacklist[word] then
                -- Analyze potential layout targets starting from our desired max length down to 1
                for testLength = UnbeatableTracker.CurrentTargetPrefixLength, 1, -1 do
                    if #word >= #requiredPrefix + testLength then
                        local potentialEnemySuffix = string.sub(word, #word - testLength + 1)
                        local validationCount = CountValidReturnsForSuffix(potentialEnemySuffix)
                        
                        -- Check if the resulting branch allows at least 3 viable responses
                        if validationCount >= 3 then
                            table.insert(candidates, {
                                word = word,
                                suffix = potentialEnemySuffix,
                                length = testLength,
                                density = validationCount
                            })
                            break
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    -- 3. Sort candidates maximizing opponent difficulty (highest tier length -> rarest paths)
    table.sort(candidates, function(a, b)
        if a.length ~= b.length then
            return a.length > b.length
        end
        return a.density < b.density
    end)

    return candidates[1].word
end

local function GetNextWord(requiredPrefix)
    if sortMode == "Unbeatable" or Config.SortMode == "Unbeatable" then
        local target = GetUnbeatableWord(requiredPrefix)
        if target then return target end
    end

    requiredPrefix = string.lower(requiredPrefix)
    for _, word in ipairs(Dictionary) do
        if string.sub(word, 1, #requiredPrefix) == requiredPrefix then
            if not UsedWords[word] and not Blacklist[word] then
                return word
            end
        end
    end
    return nil
end

        end
    end
    return nil
end

print("WordHelper initialized successfully. Master dictionary active with " .. #Dictionary .. " entries.")
print("Current active mode set to: " .. tostring(Config.SortMode))
]=]

task.spawn(function()
    if writefile then
        writefile(WORDHELPER_FILE, WORDHELPER_SOURCE)
    end
    loadstring(WORDHELPER_SOURCE)()
end)
