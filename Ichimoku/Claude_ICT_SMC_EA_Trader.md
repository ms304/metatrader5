## Ce que fait l'EA

**Concepts ICT/SMC intégrés :**

- **Order Blocks** — détecte la dernière bougie bearish avant un move haussier (OB bull) et inversement (OB bear), avec vérification si la zone a déjà été mitigée
- **FVG (Fair Value Gap)** — détecte les imbalances 3 bougies (candle[i].low > candle[i+2].high pour un FVG bull), avec taille minimale configurable
- **MSS (Market Structure Shift)** — détecte la cassure d'un swing high/low qui marque le changement de structure
- **PDH/PDL/PWH/PWL** — calculés automatiquement depuis les bougies Daily et Weekly
- **Swings H/L** — détectés sur M1, M5 et M15 simultanément

**Logique d'entrée :**

Chaque signal exige un alignement sur les 3 timeframes. Pour un LONG par exemple : biais M15 haussier + biais M5 non-baissier + MSS bull + OB bull accessible + FVG bull (toutes ces conditions sont paramétrables individuellement).

**Gestion du risque :**

Le calcul des lots utilise `tickSize` et `tickValue` pour être précis sur tout actif (forex, indices, matières premières, crypto). Le SL est placé sous le dernier swing low + buffer. Le TP cible le prochain swing high ou PDH/PWH, avec un ratio minimum 1:2 garanti avant d'entrer.

**À noter pour l'installation :**
1. Copier dans `MQL5/Experts/`
2. Compiler dans MetaEditor (F7)
3. Autoriser le trading automatique
4. Tester d'abord sur **démo** — ajuster `SwingLookback`, `OB_Lookback`, `FVG_MinPoints` selon l'actif
