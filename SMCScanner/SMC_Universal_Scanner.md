C'est une excellente idée. Pour répliquer ce qui s'est passé aujourd'hui (le "Turtle Soup" suivi d'un déplacement), nous devons traduire des concepts visuels en règles mathématiques strictes.

Voici un Expert Advisor (EA) complet pour MT5 qui automatise la détection du setup **SMC (Liquidity Sweep + Rejection + Displacement)**.

Il fonctionne dans les deux sens (Long et Short) et scanne le marché à chaque clôture de bougie.

### La Logique de l'EA (Le Cerveau)
L'EA cherche 3 conditions précises pour valider un signal, calquées sur votre trade de 16h15 :

1.  **La Prise de Liquidité (Sweep) :** Le prix doit percer un plus haut ou un plus bas récent (Swing High/Low) de X périodes.
2.  **La Réintégration (Rejection) :** Le prix ne doit pas rester hors de la zone. Il doit clôturer en sens inverse (ex: mèche basse, mais clôture haussière).
3.  **Le Déplacement (Displacement) :** La bougie de signal doit être "puissante". Son corps doit être supérieur à la moyenne des bougies précédentes (pour éviter les faux signaux dans un marché mou).

---

### Code Source MQL5 (SMC_Universal_Scanner.mq5)

Copiez ce code dans votre MetaEditor (Touche F4 sur MT5), compilez-le (F7), et glissez-le sur le graphique.

```cpp
//+------------------------------------------------------------------+
//|                                       SMC_Universal_Scanner.mq5  |
//|               Détecteur de Liquidity Sweeps & Market Structure   |
//|                      Compatible: XAUUSD, Forex, Indices          |
//+------------------------------------------------------------------+
#property copyright "SMC Automated"
#property version   "1.00"
#include <Trade\Trade.mqh>

//--- INPUTS ---
input group "--- PARAMETRES SMC ---"
input int      LookbackPeriod = 20;     // Période pour définir la Liquidité (Swing)
input double   DisplacementFactor = 1.2; // Force du mouvement (1.0 = Moyenne, 1.5 = Fort)
input bool     FilterByTrend = true;    // Si true, trade seulement dans le sens de la MM200

input group "--- GESTION TRADING ---"
input bool     EnableTrading = false;   // Mettre 'true' pour que l'EA prenne les trades
input double   RiskPercent = 1.0;       // Risque par trade (% du capital)
input double   RiskReward = 2.0;        // Ratio Gain/Risque (TP = 2x SL)

//--- VARIABLES ---
CTrade trade;
int handleATR;
int handleMA;
double atrBuffer[];
double maBuffer[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialisation des indicateurs pour le filtre et la volatilité
   handleATR = iATR(_Symbol, _Period, 14);
   handleMA  = iMA(_Symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleATR == INVALID_HANDLE || handleMA == INVALID_HANDLE)
      return(INIT_FAILED);
      
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Fonction Principale (A chaque Tick)                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   // On travaille uniquement à la CLÔTURE de la bougie pour valider le setup
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(lastBarTime == currentBarTime) return; // Attend la prochaine bougie
   lastBarTime = currentBarTime;

   // --- 1. RECUPERATION DONNEES ---
   double close1 = iClose(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   
   // Récupérer le plus bas et plus haut des 'LookbackPeriod' bougies PRECEDENTES (de 2 à 22 par ex)
   double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackPeriod, 2));
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackPeriod, 2));

   // Calcul de la taille moyenne des bougies (pour le Displacement)
   CopyBuffer(handleATR, 0, 1, 1, atrBuffer);
   double currentATR = atrBuffer[0];
   double bodySize = MathAbs(close1 - open1);

   // Tendance de fond (EMA 200)
   CopyBuffer(handleMA, 0, 1, 1, maBuffer);
   double ema200 = maBuffer[0];

   // --- 2. LOGIQUE DU SETUP ---
   
   // --- SETUP ACHAT (LONG) : "Turtle Soup Bullish" ---
   // Condition A: On a méché SOUS le plus bas récent (Prise de liquidité)
   bool sweptLow = (low1 < lowestLow);
   // Condition B: Mais on a clôturé AU-DESSUS de ce bas (Rejection/Reclaim)
   bool reclaimed = (close1 > lowestLow);
   // Condition C: La bougie est verte (Acheteuse)
   bool isGreen = (close1 > open1);
   // Condition D: Déplacement (Corps de la bougie > ATR * Facteur)
   bool strongMove = (bodySize > currentATR * DisplacementFactor);
   // Condition E: Filtre Tendance (Prix > EMA200) - Optionnel
   bool trendFilterBuy = (!FilterByTrend || close1 > ema200);

   if(sweptLow && reclaimed && isGreen && strongMove && trendFilterBuy)
     {
      string msg = "🟢 SMC BUY SIGNAL: Liquidity Sweep + Displacement";
      SendSignal(ORDER_TYPE_BUY, low1, msg);
     }

   // --- SETUP VENTE (SHORT) : "Turtle Soup Bearish" ---
   // Condition A: On a méché AU-DESSUS du plus haut récent
   bool sweptHigh = (high1 > highestHigh);
   // Condition B: Mais on a clôturé EN-DESSOUS (Rejection)
   bool rejected = (close1 < highestHigh);
   // Condition C: La bougie est rouge (Vendeuse)
   bool isRed = (close1 < open1);
   // Condition D & E
   bool trendFilterSell = (!FilterByTrend || close1 < ema200);

   if(sweptHigh && rejected && isRed && strongMove && trendFilterSell)
     {
      string msg = "🔴 SMC SELL SIGNAL: Liquidity Sweep + Displacement";
      SendSignal(ORDER_TYPE_SELL, high1, msg);
     }
  }

//+------------------------------------------------------------------+
//| Gestion des Ordres et Alertes                                    |
//+------------------------------------------------------------------+
void SendSignal(ENUM_ORDER_TYPE type, double swingPoint, string comment)
  {
   // 1. Envoyer les Alertes
   Alert(comment + "\nSymbol: " + _Symbol + "\nPrice: " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), 2));
   SendNotification(comment); // Pour mobile

   // 2. Exécuter le Trade (Si activé)
   if(EnableTrading)
     {
      double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0;
      double tp = 0;
      
      // Stop Loss juste derrière la mèche de liquidation (Swing Point)
      if(type == ORDER_TYPE_BUY)
        {
         sl = swingPoint; // SL sous le plus bas de la mèche
         double dist = price - sl;
         tp = price + (dist * RiskReward);
        }
      else
        {
         sl = swingPoint; // SL au-dessus du plus haut de la mèche
         double dist = sl - price;
         tp = price - (dist * RiskReward);
        }
        
      // Calcul taille de lot (simplifié)
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * (RiskPercent / 100.0);
      // Note: Le calcul précis du lot dépend de la valeur du tick, ici 0.01 par défaut pour sécurité
      double volume = 0.01; 

      trade.PositionOpen(_Symbol, type, volume, price, sl, tp, comment);
     }
  }
//+------------------------------------------------------------------+
```

### Comment utiliser cet EA pour détecter le prochain "Big Move" ?

1.  **L'Installation :**
    *   Même procédure : Copiez le code -> MetaEditor -> Nouveau -> Coller -> Compiler -> Glisser sur le graphique.

2.  **Les Réglages Clés (Inputs) :**
    *   **LookbackPeriod (Défaut: 20) :** C'est la mémoire du marché.
        *   Mettez **10 à 20** pour du Scalping (M5/M15). Cela détecte les petits sweeps rapides.
        *   Mettez **50 à 100** pour du Swing (H1/H4). Cela détecte les prises de liquidités majeures (comme les plus bas de la semaine).
    *   **DisplacementFactor (Défaut: 1.2) :** C'est le filtre de "puissance".
        *   Plus ce chiffre est haut (ex: 1.5 ou 2.0), moins vous aurez de signaux, mais plus ils seront fiables (grosses bougies impulsives uniquement).
    *   **EnableTrading :** Laissez sur `false` au début. L'EA vous enverra juste des alertes (pop-up + son). Mettez sur `true` seulement après avoir testé en démo.

3.  **Sur quelle Timeframe l'utiliser ?**
    *   Pour reproduire le succès d'aujourd'hui : **M15** est le roi.
    *   Le M15 élimine le bruit du M1/M5 mais réagit assez vite pour attraper le début du mouvement.

### Ce que cet EA va détecter
Si demain, le prix de l'or monte à 4 880 $, fait une mèche à 4 890 $ (faux break de l'ATH) puis redescend brutalement avec une grosse bougie rouge qui clôture sous 4 880 $ :
*   L'EA identifiera : **Sweep (ATH) + Rejection + Displacement.**
*   Il vous enverra une alerte : **"🔴 SMC SELL SIGNAL"**.

C'est votre outil de surveillance automatique pour ne plus rater ces mouvements quand vous n'êtes pas devant l'écran.
