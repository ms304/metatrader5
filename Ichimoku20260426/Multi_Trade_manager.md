# 📚 DOCUMENTATION COMPLÈTE - MULTI TRADE MANAGER V2.00

## Table des matières
1. [Présentation générale](#présentation-générale)
2. [Installation](#installation)
3. [Configuration du fichier CSV](#configuration-du-fichier-csv)
4. [Paramètres d'entrée](#paramètres-dentrée)
5. [Fonctionnement détaillé](#fonctionnement-détaillé)
6. [Calcul automatique des lots](#calcul-automatique-des-lots)
7. [Exemples d'utilisation](#exemples-dutilisation)
8. [Logs et alertes](#logs-et-alertes)
9. [Dépannage](#dépannage)
10. [Spécifications techniques](#spécifications-techniques)

---

## Présentation générale

Le **Multi Trade Manager** est un Expert Advisor (EA) pour MetaTrader 5 qui permet de gérer **automatiquement plusieurs trades** sur différents actifs simultanément, en se basant sur un fichier de configuration CSV.

### Fonctionnalités principales

| Fonctionnalité | Description |
|----------------|-------------|
| ✅ **Multi-actifs** | Surveille plusieurs symboles simultanément |
| ✅ **Configuration CSV** | Paramètres modifiables sans recompilation |
| ✅ **LONG / SHORT** | Support des deux directions de trade |
| ✅ **Clôture bougie M5** | Déclenchement sur clôture de bougie 5 minutes |
| ✅ **Calcul auto lots** | Option de calcul des lots basé sur le risque |
| ✅ **Stop Loss & Take Profit** | Gestion complète des niveaux de sortie |
| ✅ **Alertes** | Alertes visuelles, sonores et notifications |

---

## Installation

### 1. Installation de l'EA

```
1. Copier le code source dans MetaEditor
2. Compiler (F7) pour générer le fichier .ex5
3. Placer l'EA sur un graphique (n'importe quel timeframe)
4. Activer le bouton "AutoTrading" (vert)
```

### 2. Installation du fichier CSV

Le fichier de configuration doit être placé dans :

```
[Données MT5]\MQL5\Files\Trades_Config.csv
```

**Chemin typique :**
- Windows : `C:\Users\VotreNom\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MQL5\Files\`
- Depuis MT5 : Fichier → Ouvrir le dossier des données → MQL5 → Files

---

## Configuration du fichier CSV

### Format du fichier

```csv
Symbole,Type,Entree,TP,SL,Lots,Actif
XAUUSD,LONG,4647.34,4669.73,4630.00,0.35,1
XAUUSD,SHORT,4647.34,4624.95,4660.00,0.35,1
EURUSD,LONG,1.08500,1.09200,1.08200,0.20,1
```

### Description des colonnes

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| **Symbole** | string | Nom de l'actif MT5 | XAUUSD, EURUSD, GBPUSD |
| **Type** | string | Direction du trade | LONG ou SHORT |
| **Entree** | double | Prix de déclenchement (clôture M5) | 4647.34 |
| **TP** | double | Take Profit (prix cible) | 4669.73 |
| **SL** | double | Stop Loss (prix de sortie risque) | 4630.00 |
| **Lots** | double | Volume en lots (fixe) | 0.35 |
| **Actif** | int | 1 = actif, 0 = désactivé | 1 |

### Règles de validation CSV

- ✅ Séparateur : **virgule (,)**
- ✅ Encodage : **ANSI** ou **UTF-8**
- ✅ Première ligne : **en-tête obligatoire**
- ✅ Lignes commençant par `#` : ignorées (commentaires)

---

## Paramètres d'entrée

### Paramètres généraux

| Paramètre | Type | Défaut | Description |
|-----------|------|--------|-------------|
| `FichierConfig` | string | "Trades_Config.csv" | Nom du fichier CSV |
| `Slippage` | int | 50 | Slippage maximum en points |
| `ActiverLogsDetails` | bool | true | Logs détaillés dans l'onglet Experts |
| `MagicNumberBase` | int | 202500 | Base pour les identifiants uniques |

### Paramètres calcul auto lots

| Paramètre | Type | Défaut | Description |
|-----------|------|--------|-------------|
| `CalculAutoLots` | bool | false | Active/désactive le calcul auto |
| `RisquePourcent` | double | 1.0 | Risque en % du compte (1.0 = 1%) |
| `StopLossPoints` | double | 500 | Distance SL par défaut en points |
| `LotsMax` | double | 5.0 | Lots maximum autorisé |
| `LotsMin` | double | 0.01 | Lots minimum autorisé |
| `UtiliserMargePourMax` | bool | false | Limite par la marge disponible |
| `PourcentageMargeMax` | double | 50.0 | % max de marge à utiliser |

---

## Fonctionnement détaillé

### 1. Cycle de surveillance

```
┌─────────────────────────────────────────────────────────┐
│                    SURVEILLANCE M5                       │
├─────────────────────────────────────────────────────────┤
│  1. Lecture fichier CSV à l'initialisation              │
│  2. Pour chaque actif configuré :                       │
│     - Vérification nouvelle bougie M5 fermée            │
│     - Comparaison prix clôture vs seuil                  │
│     - Condition validée → exécution trade               │
│  3. Une seule exécution par configuration               │
└─────────────────────────────────────────────────────────┘
```

### 2. Conditions de déclenchement

| Type | Condition |
|------|-----------|
| **LONG** | `Clôture bougie M5 > Prix d'entrée` |
| **SHORT** | `Clôture bougie M5 < Prix d'entrée` |

### 3. Timeframe utilisé

- **Timeframe fixe : M5 (5 minutes)**
- La vérification s'effectue à la **fermeture effective** de chaque bougie

### 4. Magic Numbers

Les magic numbers sont générés automatiquement :
```
MagicNumber = MagicNumberBase + index_dans_CSV
```

Exemple :
- Trade #1 : 202501
- Trade #2 : 202502
- Trade #3 : 202503

---

## Calcul automatique des lots

### Formule de calcul

```
Lots = (Capital × Risque%) / (Distance SL × Valeur du point)
```

### Étapes du calcul

```
┌─────────────────────────────────────────────────────────┐
│               ALGORITHME CALCUL LOTS AUTO               │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. Capital = Balance du compte                         │
│  2. Risque € = Capital × (RisquePourcent / 100)        │
│  3. Valeur point = SymbolInfoDouble(SYMBOL_TRADE_TICK_VALUE) │
│  4. Perte max par lot = Distance SL × Valeur point      │
│  5. Lots = Risque € / Perte max par lot                 │
│  6. Application limites LotsMin / LotsMax               │
│  7. Arrondi au step lot du broker                       │
│  8. Si UtiliserMargePourMax = true :                    │
│        lots = min(lots, MargeDispo × %Marge / MargeParLot) │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Exemple de calcul

| Variable | Valeur |
|----------|--------|
| Capital | 10 000 € |
| Risque % | 1% |
| Risque € | 100 € |
| Distance SL | 500 points |
| Valeur point XAUUSD | 0.10 €/lot |
| Perte max par lot | 500 × 0.10 = 50 € |
| **Lots calculés** | **100 / 50 = 2.0 lots** |

---

## Exemples d'utilisation

### Exemple 1 : Trade LONG simple sur Or

**CSV :**
```csv
Symbole,Type,Entree,TP,SL,Lots,Actif
XAUUSD,LONG,4647.34,4669.73,4630.00,0.35,1
```

**Comportement :**
- Surveille XAUUSD en M5
- Dès qu'une bougie ferme au-dessus de 4647.34
- Entre en LONG 0.35 lots
- Take Profit à 4669.73
- Stop Loss à 4630.00

### Exemple 2 : Multi-actifs avec calcul auto lots

**CSV :**
```csv
Symbole,Type,Entree,TP,SL,Lots,Actif
XAUUSD,LONG,4647.34,4669.73,4630.00,0,1
EURUSD,SHORT,1.09200,1.08500,1.09500,0,1
GBPUSD,LONG,1.30000,1.31000,1.29500,0,1
```

**Paramètres EA :**
- `CalculAutoLots = true`
- `RisquePourcent = 1.0`
- `StopLossPoints = 500`

**Comportement :**
- Les lots sont calculés automatiquement au moment du déclenchement
- Chaque trade risque 1% du compte
- Les valeurs `Lots` du CSV (0) sont ignorées

### Exemple 3 : Trade désactivé

**CSV :**
```csv
Symbole,Type,Entree,TP,SL,Lots,Actif
XAUUSD,LONG,4647.34,4669.73,4630.00,0.35,0
```

**Comportement :**
- Le trade est ignoré (Actif = 0)
- Peut être réactivé en changeant la valeur à 1

---

## Logs et alertes

### Types d'alertes

| Type | Déclenchement | Format |
|------|---------------|--------|
| **Print** | À chaque événement | Texte dans onglet "Experts" |
| **Alert** | Trade exécuté | Popup à l'écran |
| **Sound** | Trade exécuté | "alert.wav" |
| **Notification** | Trade exécuté | Push MT5 mobile (si configuré) |

### Exemple de logs

```
═══════════════════════════════════════════════════════
⭐ MULTI TRADE MANAGER V2 - INITIALISATION ⭐
═══════════════════════════════════════════════════════
📊 MODE LOTS FIXES (depuis CSV)
✅ Configuration chargée - 1 trade(s) paramétré(s)
═══════════════════════════════════════════════════════
[1] XAUUSD - LONG | Entrée: 4647.34 | TP: 4669.73 | SL: 4630.00 | Lots: 0.35
═══════════════════════════════════════════════════════

📌 [XAUUSD] Nouvelle bougie fermée
   Heure: 2026.04.30 14:50:00
   Clôture: 4648.50
   Seuil LONG: 4647.34
🎯 Condition LONG validée pour XAUUSD

🚀 EXÉCUTION TRADE
   Actif    : XAUUSD
   Type     : LONG
   Lots     : 0.35 (fixe)
   Entrée   : 4648.55
   TP       : 4669.73
   SL       : 4630.00
   Trigger  : 4648.50
═══════════════════════════════════════════════════════
✅✅✅ TRADE EXÉCUTÉ AVEC SUCCÈS ! ✅✅✅
   Ticket: 12345678
   Prix entrée: 4648.55
   Lots exécutés: 0.35
```

---

## Dépannage

### Erreurs fréquentes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Fichier introuvable` | CSV absent ou mauvais chemin | Vérifier dossier `MQL5\Files\` |
| `Symbole non disponible` | Actif inexistant | Vérifier nom du symbole |
| `Marge insuffisante` | Fonds insuffisants | Réduire lots ou ajouter fonds |
| `Trade désactivé` | AutoTrading off | Activer bouton vert |
| `Marché fermé` | Hors horaires trading | Attendre ouverture |

### Vérification rapide

```mql5
// Ajouter ce code temporaire pour debug
Print("Dossier des fichiers: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\");
Print("Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
Print("Marge libre: ", AccountInfoDouble(ACCOUNT_MARGIN_FREE));
```

---

## Spécifications techniques

### Compatibilité

| Élément | Version |
|---------|---------|
| **Plateforme** | MetaTrader 5 |
| **Langage** | MQL5 |
| **Timeframe requis** | M5 (recommandé, peut fonctionner sur d'autres) |
| **Actifs supportés** | Forex, Métaux, Indices, Crypto (selon broker) |

### Ordres de priorité

```
1. Vérification marge suffisante
2. Si CalculAutoLots = true → calcul dynamique
3. Si marge insuffisante → tentative réduction lots
4. Exécution ordre marché (MARKET ORDER)
5. Pose SL/TP
```

### Limitations

| Limitation | Détail |
|------------|--------|
| **1 trade par configuration** | Une fois déclenché, ne se répète pas |
| **Timeframe fixe** | M5 uniquement |
| **Fermeture bougie** | Pas d'exécution intra-bougie |
| **Pas de trailing stop** | Fonctionnalité non implémentée |

---

## Notes importantes

⚠️ **Testez toujours en démo avant le réel**

⚠️ **Le Stop Loss est obligatoire pour le calcul auto lots**

⚠️ **Les alertes Push nécessitent configuration MT5 (Outils → Options → Notifications)**

⚠️ **Le fichier CSV n'est lu qu'à l'initialisation (redémarrer l'EA après modification)**

---

## Support et mises à jour

| Version | Date | Modifications |
|---------|------|---------------|
| 1.00 | - | Version initiale |
| 2.00 | - | Ajout calcul auto lots + Multi-actifs |

---

**Documentation générée le :** Avril 2026
**EA Version :** 2.00
**Auteur :** Multi Trade Manager
