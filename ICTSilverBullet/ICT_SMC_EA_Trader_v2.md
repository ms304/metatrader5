

Par défaut, cet EA est paramétré pour les **paires de devises Forex (Majors)**, plus précisément pour des instruments comme l'**EUR/USD** ou le **GBP/USD**.

Voici pourquoi :

1.  **Le paramètre `FVG_MinSize = 0.0005`** :
    *   Pour l'EURUSD, 0.0005 représente **5 pips** (ou 50 points sur un compte à 5 décimales). C'est une taille de gap standard et pertinent pour ce type d'actif.
    *   Si tu l'utilises sur l'Or (XAUUSD), 0.0005 est beaucoup trop petit (l'or bouge de 5, 10, 50 dollars).
    *   Si tu l'utilises sur un Indice (comme le Dow Jones ou DAX), 0.0005 ne veut rien dire car ces indices bougent par points entiers (ex: 50 points, 100 points).

2.  **Le Stop Loss / Take Profit (`500` points)** :
    *   Sur un courtier "5 chiffres" (ex: 1.08500), 500 points équivalent à **50 pips**. C'est une distance de protection classique pour une stratégie ICT sur le Forex H1/H4.

---

### Comment ajuster pour d'autres actifs ?

Si tu souhaites utiliser cet EA sur d'autres marchés, tu dois modifier impérativement le paramètre **`FVG_MinSize`** dans les paramètres de l'EA :

*   **OR (XAUUSD) / Indices (US30, NASDAQ) :** Remplace `0.0005` par une valeur entre **5.0** et **50.0** (selon si tu veux des petits ou gros gaps).
*   **USDJPY :** Remplace `0.0005` par **0.05** (le Yen a généralement 2 ou 3 décimales).
*   **Crypto (BTCUSD) :** Remplace `0.0005` par une valeur comme **100** ou **500** (car le Bitcoin a une amplitude de prix énorme).

**Résumé :** Tu peux le tester tel quel sur **EURUSD** ou **GBPUSD** en timeframe H1 ou H4. Pour tout autre chose, change le `FVG_MinSize`.
