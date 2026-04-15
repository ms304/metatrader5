//@version=5
indicator("ICT AMD / BSL-SSL Sweep [Sur-mesure]", overlay=true, max_lines_count=50, max_labels_count=50)

// --- INPUTS ---
leftLen = input.int(15, title="Pivot Left (Bougies avant)", minval=1)
rightLen = input.int(5, title="Pivot Right (Bougies après)", minval=1)
useFVG = input.bool(true, title="Exiger un FVG pour le Pullback ?")

// --- VARIABLES DE STRUCTURE ---
var float ssl_level = na
var float bsl_level = na
var int ssl_time = na
var int bsl_time = na

var bool waiting_for_sweep = false
var bool sweep_in_progress = false
var float local_mss_high = na

// --- DETECTION DES PIVOTS (SWINGS) ---
ph = ta.pivothigh(high, leftLen, rightLen)
pl = ta.pivotlow(low, leftLen, rightLen)

// 1. Enregistrement du SSL (Préexistant)
if not na(pl)
    ssl_level := pl
    ssl_time := time[rightLen]
    waiting_for_sweep := false
    sweep_in_progress := false

// 2. Enregistrement du BSL (Créé APRÈS le SSL)
if not na(ph) and not na(ssl_level) and time[rightLen] > ssl_time
    bsl_level := ph
    bsl_time := time[rightLen]
    waiting_for_sweep := true
    sweep_in_progress := false
    
    // Tracer la ligne BSL (Objectif)
    line.new(bsl_time, bsl_level, time, bsl_level, xloc=xloc.bar_time, color=color.blue, style=line.style_solid, width=2)
    // Tracer la ligne SSL (Zone à sweeper)
    line.new(ssl_time, ssl_level, time, ssl_level, xloc=xloc.bar_time, color=color.red, style=line.style_dashed, width=2)

// --- DETECTION DU SWEEP (Prise de liquidité) ---
if waiting_for_sweep and low < ssl_level and not sweep_in_progress
    sweep_in_progress := true
    waiting_for_sweep := false
    local_mss_high := high[1] // On traque le haut de la bougie précédente pour le MSS
    label.new(bar_index, low, "🧹 SWEEP", style=label.style_label_up, color=color.new(color.red, 80), textcolor=color.red, size=size.small)

// Mise à jour du Market Structure Shift (Plus haut local pendant la chute)
if sweep_in_progress
    local_mss_high := math.min(local_mss_high, ta.highest(high, 3)) 

// --- DETECTION DU PULLBACK (MSS / FVG) ---
// Condition FVG Haussier : Le plus bas actuel est au-dessus du plus haut d'il y a 2 bougies
bullish_fvg = low > high[2] and close[1] > open[1]

// Cassure de structure (Clôture au-dessus du dernier petit sommet)
mss_break = close > local_mss_high

// Validation de l'entrée selon le choix de l'utilisateur
pullback_valid = sweep_in_progress and (useFVG ? (bullish_fvg and close > open) : mss_break)

if pullback_valid
    label.new(bar_index, low, "🚀 ENTRY\nTarget BSL", style=label.style_label_up, color=color.new(color.green, 50), textcolor=color.white, size=size.small)
    // Dessiner une ligne de target jusqu'au BSL
    line.new(bar_index, close, bar_index + 10, bsl_level, color=color.green, style=line.style_dotted, width=2)
    
    // Reset du setup pour chercher le prochain cycle
    sweep_in_progress := false
    ssl_level := na
    bsl_level := na

// Alertes
alertcondition(pullback_valid, title="ICT Pullback Validé !", message="Le prix a sweepé le SSL pré-existant et validé un Pullback. Target : BSL.")
