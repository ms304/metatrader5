Voici les critères exacts implémentés dans l'EA, dans l'ordre d'évaluation :

---

## 🔎 Critères d'entrée en position

### Étape 1 — Filtre préalable (éliminatoire)
Avant même d'analyser un actif, l'EA vérifie :
- ✅ Le symbole est **disponible au trading** sur le broker
- ✅ L'**historique est suffisant** (250 bougies minimum sur H4 et H1)
- ✅ Le **spread est acceptable** — calculé en % du prix, adaptatif selon le type d'actif :
  - Forex majeurs → max 0.05%
  - Pétrole, indices mid → max 0.10%
  - Or, grands indices → max 0.15%
  - Crypto / exotiques → max 0.30%

---

### Étape 2 — Tendance H4 (obligatoire)
L'EA calcule les **EMA 50 et EMA 200** sur H4.

| Condition BUY | Condition SELL |
|---|---|
| EMA50 **au-dessus** de EMA200 | EMA50 **en dessous** de EMA200 |
| Prix **au-dessus** de EMA50 | Prix **en dessous** de EMA50 |

➡️ Si aucune tendance claire → **symbole ignoré**

---

### Étape 3 — Zone de retracement Fibonacci (obligatoire)
L'EA détecte le **swing high et swing low** des 20 dernières bougies H1, puis vérifie que le prix actuel se trouve dans la **zone 50-65% de retracement** de ce swing.

- En tendance haussière → le prix doit être en train de **retomber** dans cette zone (pullback)
- En tendance baissière → le prix doit être en train de **remonter** dans cette zone (retracement)

➡️ Si le prix est hors zone → **symbole ignoré**

---

### Étape 4 — Confirmation RSI H1 (+1 point de score)
Le **RSI 14** sur H1 doit confirmer la direction :

| BUY | SELL |
|---|---|
| RSI ≤ 50 (zone survente relative) | RSI ≥ 50 (zone surachat relatif) |

➡️ Si RSI est en sens inverse → **symbole ignoré**

---

### Étape 5 — Bougie de confirmation H1 (+1 point de score)
L'EA cherche une bougie de confirmation sur la dernière bougie clôturée :

**Pin bar** → longue mèche (>60% du range) dans le sens du rejet, petit corps (<30% du range)

**Englobante** → la bougie actuelle englobe entièrement le corps de la précédente, dans le sens de la tendance

➡️ Si présente → score +1, mais **non bloquante** (l'EA peut trader sans elle si score ≥ 2)

---

### Étape 6 — Vérification du ratio R:R (obligatoire)
Le SL est placé **au-delà du swing high/low + 5% de marge**, et l'EA vérifie que le TP à 2× cette distance est **réaliste** avant d'ouvrir.

---

### Étape 7 — Sélection du meilleur setup
Si **plusieurs actifs** passent tous les filtres simultanément, l'EA sélectionne celui avec le **score de confluence le plus élevé** (max 3 points). En cas d'égalité, il prend celui avec le **meilleur RR calculé**.

---

## En résumé visuel

```
[Spread OK]
     ↓
[Tendance H4 claire — EMA 50/200]       ← OBLIGATOIRE
     ↓
[Prix dans zone Fibo 50-65%]             ← OBLIGATOIRE
     ↓
[RSI confirme la direction]              ← +1 point
     ↓
[Bougie de confirmation présente]        ← +1 point
     ↓
[Score ≥ 2 → Trade ouvert]
```

Le score **minimum pour trader est 2/3** — ce qui correspond au moins à la tendance + Fibonacci + RSI, la configuration la plus fiable statistiquement.
