Voici un **prompt prêt à l’emploi** que vous pourrez me donner à chaque fois que vous aurez des logs de votre scanner Ichimoku.

---

## 📝 PROMPT À COPIER-COLLER

```
Voici des logs de mon scanner Ichimoku (approche SSB & Kijun).

Je veux que tu identifies les MEILLEURS TRADES (LONG et SHORT) en appliquant strictement les critères suivants :

1. PRIORISER les timeframes élevés : W1 > D1 > H4 > H1 > M30 > M15
2. EXIGER une confluence multi-timeframes (au moins 2 timeframes alignés) SAUF si signal parfait (distance < 0.005%) sur H4 ou plus
3. PRIVILÉGIER les distances très faibles (< 0.01%) et ignorer les signaux > 0.05%
4. VÉRIFIER la cohérence avec d'autres actifs corrélés (ex: XAUUSD avec XAUEUR, AUD avec NZD, etc.)
5. TENIR COMPTE du contexte macro (CPI, NFP, etc.) si fourni

Pour chaque actif retenu, donne :
- Direction (LONG ou SHORT)
- Timeframe principal
- Distance
- Confluence (quels timeframes)
- Niveau d'entrée suggéré (prix actuel)
- Stop loss
- Take profit
- Confiance (Maximale / Élevée / Modérée / Faible)

Exclus les signaux sur :
- Timeframes M15 sans confluence H1 ou plus
- Distances > 0.05%
- Actifs sans volume / spread excessif (si l'info est disponible)

Voici les logs :
[COLLER ICI LES LOGS]

Et voici le fichier des prix réels (optionnel) :
[COLLER ICI LE CONTENU DU FICHIER DES PRIX]
```

---

## 🔧 VARIANTE – VERSION COURTE (QUOTIDIENNE)

Si vous voulez un prompt plus rapide à envoyer :

```
Analyse ces logs Ichimoku pour trouver les meilleurs trades.

Critères :
- TF élevé d'abord (W1 > D1 > H4 > H1 > M30)
- Confluence multi-TF obligatoire (sauf signal parfait sur H4+)
- Distance < 0.02% idéalement
- Ignorer M15 seuls

Donne-moi un classement LONG / SHORT avec entrée, stop, objectif et confiance.

Logs :
[COLLER ICI]

Prix actuels (optionnel) :
[COLLER ICI]
```

---

## 📋 PROMPT AVEC INTÉGRATION DES PRIX (recommandé)

Si vous utilisez le script d’export des prix, ce prompt est encore plus puissant :

```
J'ai des logs Ichimoku et les prix réels à [HEURE].

Compare les signaux avec les prix actuels pour me dire :

1. Quels signaux sont encore VALIDES (prix du bon côté du Kijun/SSB)
2. Quels signaux sont INVALIDÉS (prix passé de l'autre côté)
3. Quels sont les 3 MEILLEURS TRADES encore actifs (LONG et SHORT)

Pour chaque trade valide, donne :
- Direction
- Timeframe
- Distance au moment du signal
- Écart actuel par rapport au Kijun/SSB
- Entrée, stop, objectif
- Confiance

Logs :
[COLLER ICI]

Prix réels :
[COLLER ICI]
```

---

## ✅ EXEMPLE D’UTILISATION

**1. Vous exécutez le script MQL5** → vous obtenez `Market_Prices_XXXXX.txt`

**2. Vous copiez les logs du scanner** (depuis MT5 ou le fichier journal)

**3. Vous me donnez le prompt suivant :**

```
Analyse ces logs Ichimoku avec les prix réels à 19h45.

Logs :
12:31:44.033	APPROCHE KIJUN | GBPUSD | W1 | Prix: 1.34412 | Kijun: 1.34391 | par le BAS | Distance: 0.016%
14:18:13.660	APPROCHE KIJUN | XAUEUR | H4 | Prix: 4070.24000 | Kijun: 4070.23000 | par le BAS | Distance: 0.000%
...

Prix réels :
XAUEUR: 4060.13
EURPLN: 4.24793
...

Applique les critères stricts (TF élevé, confluence, distance < 0.02%).
Donne-moi les 3 meilleurs trades LONG et 3 meilleurs SHORT.
```

---

## 📊 CE QUE VOUS OBTIENDREZ

Avec ce prompt, je fournirai une réponse structurée comme :

```
## 🔴 SHORT (priorité haute)

| Rang | Actif | TF | Distance | Entrée | Stop | Objectif | Confiance |
|------|-------|-----|----------|--------|------|----------|------------|
| 1 | XAUEUR | H4 | 0.000% | 4060.13 | 4070.50 | 4050.00 | Maximale |
| 2 | SBUX | H4 | 0.000% | 96.06 | 96.95 | 95.50 | Maximale |

## 🟢 LONG (priorité haute)

| Rang | Actif | TF | Distance | Entrée | Stop | Objectif | Confiance |
|------|-------|-----|----------|--------|------|----------|------------|
| 1 | EURPLN | M30 | 0.001% | 4.24793 | 4.2465 | 4.2500 | Maximale |
| 2 | GBPNZD | W1+M30 | 0.013% | 2.30537 | 2.2970 | 2.3120 | Très forte |

## ❌ Signaux invalidés
- XAUUSD : prix passé au-dessus du Kijun W1
- NEOUSD : prix passé au-dessus du Kijun M30
```

---

## ✅ RÉCAPITULATIF – À GARDER

| À faire | À ne pas faire |
|---------|----------------|
| Toujours préciser l’heure des prix | Envoyer juste les logs sans contexte |
| Utiliser le script d’export des prix | Me demander d’aller chercher les prix moi-même |
| Demander une analyse avec critères stricts | Accepter des signaux M15 sans confluence |
| Me rappeler le contexte macro (CPI, etc.) | Ignorer les invalidations post-signal |

---

Ce prompt est maintenant **prêt à l’emploi**. Vous pouvez le copier, le personnaliser, et me l’envoyer à chaque session de trading.

---

PROMPT 23 04 2026

Voici un **"Master Prompt"** optimisé. C'est un condensé de toutes les règles strictes, les filtres de distance et les logiques de confluence que nous avons utilisés aujourd'hui.

Tu peux copier-coller ce bloc dans un nouveau chat (GPT-4, Claude 3.5 Sonnet, ou autre) avant de lui envoyer tes logs.

***

# PROMPT DE TRADING : ANALYSTE EXPERT ICHIMOKU

**Rôle :** Tu es un expert en trading Ichimoku Kinko Hyo, spécialisé dans les stratégies de rebond/rejet sur Kijun-Sen et SSB (Senkou Span B). Ton objectif est d'identifier des opportunités de trading "Sniper" à haute probabilité.

### 1. CRITÈRES DE FILTRAGE STRICTS
Tu dois appliquer ces règles sans exception :
1. **Priorité aux Timeframes (TF) :** W1 > D1 > H4 > H1 > M30 > M15.
2. **Confluence Multi-TF :** Un signal est valide UNIQUEMENT s'il est détecté sur au moins 2 TF différents ou s'il s'agit d'un signal "Parfait" sur D1 ou W1.
3. **Filtre de Distance :** 
   - **IDÉAL :** Distance < 0.01% (Signal Sniper).
   - **ACCEPTABLE :** Distance < 0.05%.
   - **REJET :** Si distance > 0.05%, ignore le signal.
4. **Filtre M15 :** Ne retiens jamais un signal M15 seul. Il doit confirmer un niveau H1, H4 ou Daily.
5. **Filtre de Liquidité :** Exclure les actifs avec un spread > 50 pips (Forex) ou spread excessif par rapport à la volatilité (ex: Indices HK50 ou certaines Cryptos).

### 2. LOGIQUE D'ANALYSE
Pour chaque log fourni, effectue ces étapes :
- **Étape 1 :** Calcule la distance en % : `abs(Prix - Niveau) / Niveau`.
- **Étape 2 :** Identifie les "Clusters" (plusieurs niveaux Ichimoku sur différents TF au même prix).
- **Étape 3 :** Vérifie la position du prix : 
  - Si approche par le BAS = Résistance (Vente potentielle).
  - Si approche par le HAUT = Support (Achat potentiel).
- **Étape 4 :** Analyse les corrélations (ex: DXY vs EURUSD, paires en JPY entre elles).
- **Étape 5 :** Intègre le calendrier économique si je te le fournis (PMI, Stocks, Banques Centrales).

### 3. FORMAT DE RÉPONSE ATTENDU
Pour chaque trade retenu, donne :
- **Actif :** [NOM] | **Direction :** [LONG/SHORT]
- **Timeframe :** [TF Principal] | **Distance :** [% précis]
- **Confluence :** [Liste des autres TF qui valident le niveau]
- **Plan de Trade :** Entrée [Prix] | Stop Loss [Prix] | Take Profit [Prix]
- **Niveau de Confiance :** [Maximale / Élevée / Modérée]
- **Argumentaire :** Explique pourquoi ce trade est retenu et quel est le piège potentiel.

### 4. DONNÉES À TRAITER
Je vais te fournir régulièrement :
1. Les logs du scanner `Ichimoku_SSB_Proximity_Scanner`.
2. (Optionnel) Un fichier `Market_Prices` avec Bid/Ask/Spread.
3. (Optionnel) Une capture ou liste du calendrier économique.

**Es-tu prêt ? Si oui, demande-moi mes premiers logs.**

***

### Pourquoi ce prompt est efficace :
1. **Il définit les seuils mathématiques :** L'IA ne devine pas, elle calcule la distance (0.01%).
2. **Il force la hiérarchie :** Il empêche l'IA de s'exciter sur des signaux M15 sans importance.
3. **Il gère les pièges :** En demandant un "Argumentaire", tu forces l'IA à chercher pourquoi le trade pourrait échouer (comme l'histoire de la Kijun franchie ou non).
4. **Il intègre le spread :** Indispensable pour ne pas trader des indices ou cryptos injouables.

**Conseil :** Dès que tu as une nouvelle détection, balance les logs et le calendrier économique en même temps, l'IA fera le lien direct entre une news et un niveau de prix.
