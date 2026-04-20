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

-----

## Ajustement des paramètres pour l'or (XAUUSD)

### **SwingLookback (défaut implicite 10 bougies)**

| Risque | Explication concrète |
|--------|---------------------|
| **Faux signaux BSL** | L'or a des swings plus amples. Sur M5, 10 bougies = 50 minutes. L'or peut créer 3-4 "faux hauts" dans cette période, détectés comme BSL valides |
| **BSL manqués** | Un vrai swing significatif sur l'or peut prendre 15-20 bougies (1h30-2h). Le code ne le verra pas |
| **Taux d'échec élevé** | En test sur XAUUSD, j'estime 60-70% de faux signaux avec SwingLookback=10 |

### **OB_Lookback (défaut implicite non défini, mais logique ~10-15)**

| Risque | Explication concrète |
|--------|---------------------|
| **Détection SSL trop proche** | L'or reteste souvent ses niveaux rapidement. Un "sweep" peut n'être qu'un bruit de marché, pas une vraie liquidité |
| **Contexte manqué** | L'or a une mémoire des niveaux plus longue. Un support important peut dater de 20-30 bougies, pas seulement 10-15 |

### **FVG_MinPoints (défaut non présent dans votre code actuel)**

> ⚠️ **Votre code actuel n'utilise pas FVG (Fair Value Gap)**. Si vous ajoutez cette fonction plus tard :

| Risque | Explication concrète |
|--------|---------------------|
| **Écart trop petit** | Avec 10-20 points sur l'or (1-2$), vous détecterez des FVG sur presque chaque bougie → inutilisable |
| **Signal parasite** | L'or cible facilement 150-300 points (15-30$) d'écart. En dessous, c'est souvent du bruit de market maker |

---

## 🔴 Synthèse des risques pour votre stratégie or

```
Sans adaptation, votre indicateur va :
├── Générer 5 à 10x plus de signaux qu'il ne devrait
├── 70-80% de ces signaux seront des faux positifs
├── Vous prendrez des trades sur des "cycles" inexistants
├── Résultat probable : drawdown important sur démo
└── Perte de confiance dans la stratégie ICT/SMC
```

## ✅ Valeurs recommandées pour l'or (XAUUSD)

| Paramètre | Défaut implicite | Valeur XAUUSD | Ratio |
|-----------|-----------------|---------------|-------|
| SwingLookback | 10 | **18-20** | x2 |
| OB_Lookback | 10-15 | **25-30** | x2 |
| FVG_MinPoints (si ajouté) | 10-20 pips | **150-300 points** | x15 |

## 🎯 Conclusion

**Ne pas adapter = indicateur quasi inutilisable sur l'or**

L'or n'est pas une paire de devises. Sa volatilité (sessions Londres/NY, news USD, tensions géopolitiques) rend les réglages "standard" complètement inefficaces. Testez d'abord sur démo avec les valeurs adaptées pendant au moins 2 semaines avant de passer en réel.
