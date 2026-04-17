//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//| AVEC TRADING AUTOMATIQUE                                         |
//+------------------------------------------------------------------+
#property version "4.08"
#property copyright "Copyright 2025, SMC EA"

// --- Paramètres d'entrée ---
input string API_KEY = "kwa fé don ?";
input int IntervalMin = 5;
input double LotSize = 0.01;           // Taille de la position
input double RiskPercent = 1.0;        // Risque en % du capital (0 = lot fixe)
input int Slippage = 30;               // Slippage en points
input int MaxSpread = 50;              // Spread maximum autorisé (en points)
input bool UseBreakeven = true;        // Activer le breakeven
input int BreakevenPips = 50;          // Pips après lesquels passer en BE
input bool UseTrailingStop = true;     // Activer le trailing stop
input int TrailingStart = 30;          // Pips pour démarrer le trailing
input int TrailingStep = 15;           // Pas du trailing stop

// --- Variables globales ---
datetime nextCallTime = 0; 
bool isFirstCall = true;
ulong magicNumber = 20250417;          // Numéro magique pour identifier les trades

//+------------------------------------------------------------------+
//| Structure pour stocker les infos de trade                        |
//+------------------------------------------------------------------+
struct TradeInfo
{
   double entry;
   double sl;
   double tp;
   bool hasTrade;
};
TradeInfo lastTrade = {0, 0, 0, false};

//+------------------------------------------------------------------+
//| Fonction pour obtenir la date formatée YYYYMMDD                   |
//+------------------------------------------------------------------+
string GetDateString()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) + 
          IntegerToString(dt.mon, 2, '0') + 
          IntegerToString(dt.day, 2, '0');
}

//+------------------------------------------------------------------+
//| Fonction pour formater la date et l'heure                        |
//+------------------------------------------------------------------+
string GetDateTimeString()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) + "-" + 
          IntegerToString(dt.mon, 2, '0') + "-" + 
          IntegerToString(dt.day, 2, '0') + " " +
          IntegerToString(dt.hour, 2, '0') + ":" +
          IntegerToString(dt.min, 2, '0') + ":" +
          IntegerToString(dt.sec, 2, '0');
}

//+------------------------------------------------------------------+
//| Fonction pour loguer la réponse COMPLETE dans un fichier texte   |
//+------------------------------------------------------------------+
void LogResponse(string response)
{
   string fileName = "Gemini_Logs_" + GetDateString() + ".txt";
   
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string separator = "\r\n================================================================================\r\n";
      string header = "[" + GetDateTimeString() + "]\r\n";
      
      FileWriteString(fileHandle, separator);
      FileWriteString(fileHandle, header);
      FileWriteString(fileHandle, response);
      FileWriteString(fileHandle, "\r\n");
      FileClose(fileHandle);
   }
   else
   {
      fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT);
      if(fileHandle != INVALID_HANDLE)
      {
         string separator = "\r\n================================================================================\r\n";
         string header = "[" + GetDateTimeString() + "]\r\n";
         FileWriteString(fileHandle, separator);
         FileWriteString(fileHandle, header);
         FileWriteString(fileHandle, response);
         FileWriteString(fileHandle, "\r\n");
         FileClose(fileHandle);
      }
      else
      {
         Print("Erreur lors de l'ouverture du fichier de log : ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Fonction pour loguer les trades                                  |
//+------------------------------------------------------------------+
void LogTrade(string message)
{
   string fileName = "Gemini_Trades_" + GetDateString() + ".txt";
   
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string logEntry = "[" + GetDateTimeString() + "] " + message + "\r\n";
      FileWriteString(fileHandle, logEntry);
      FileClose(fileHandle);
   }
   else
   {
      fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT);
      if(fileHandle != INVALID_HANDLE)
      {
         string logEntry = "[" + GetDateTimeString() + "] " + message + "\r\n";
         FileWriteString(fileHandle, logEntry);
         FileClose(fileHandle);
      }
   }
}

//+------------------------------------------------------------------+
//| Calcul de la taille de lot dynamique                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(RiskPercent <= 0 || slPips <= 0)
      return LotSize;
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slValue = slPips * point;
   
   if(tickValue == 0 || slValue == 0)
      return LotSize;
   
   double lot = riskAmount / (slValue * tickValue);
   
   // Arrondir au lot minimum autorisé
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Vérification des conditions de trading                          |
//+------------------------------------------------------------------+
bool CanTrade()
{
   // Vérifier si le trading auto est autorisé
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Trading automatique non autorisé");
      return false;
   }
   
   // Vérifier si le compte est en mode trading
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ||
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_CONTEST)
   {
      // OK pour démo/contest
   }
   else if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
   {
      // OK pour réel aussi
   }
   
   // Vérifier le spread
   int currentSpread = (int)MathRound((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   if(currentSpread > MaxSpread)
   {
      Print("Spread trop élevé: ", currentSpread, " > ", MaxSpread);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Exécution d'un trade LONG                                        |
//+------------------------------------------------------------------+
bool ExecuteLongTrade(double entry, double sl, double tp)
{
   if(!CanTrade())
      return false;
   
   // Vérifier si un trade similaire est déjà ouvert
   if(PositionSelectByTicket(GetLastPositionTicket()))
   {
      Print("Position déjà ouverte, pas de nouvelle entrée");
      return false;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Calcul du SL et TP en prix
   double slPrice = sl;
   double tpPrice = tp;
   
   // Calcul du lot
   double slPips = MathAbs(entry - sl) / point;
   double lot = CalculateLotSize(slPips);
   
   // Préparation de la requête
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = slPrice;
   request.tp = tpPrice;
   request.deviation = Slippage;
   request.magic = magicNumber;
   request.comment = "Gemini SMC Long";
   request.type_filling = ORDER_FILLING_FOK;
   
   Print("=== TENTATIVE DE TRADE LONG ===");
   Print("Entrée: ", ask);
   Print("SL: ", slPrice);
   Print("TP: ", tpPrice);
   Print("Lot: ", lot);
   Print("=================================");
   
   if(OrderSend(request, result))
   {
      Print("Trade exécuté avec succès! Ticket: ", result.order);
      LogTrade(StringFormat("LONG ENTRY: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.2f, Ticket=%d", ask, slPrice, tpPrice, lot, result.order));
      return true;
   }
   else
   {
      Print("Erreur d'exécution: ", GetLastError(), " - ", result.retcode_external);
      LogTrade(StringFormat("LONG FAILED: Erreur %d", GetLastError()));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Récupère le ticket de la dernière position                       |
//+------------------------------------------------------------------+
ulong GetLastPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            return ticket;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Gestion du breakeven et trailing stop                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = (currentPrice - openPrice) / point;
      
      // Breakeven
      if(UseBreakeven && profitPips >= BreakevenPips && (sl < openPrice))
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol = _Symbol;
         request.sl = openPrice + (int)(5 * point); // SL à 0.5 pip au-dessus du prix d'entrée
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(OrderSend(request, result))
         {
            Print("Breakeven activé pour le ticket ", ticket);
            LogTrade(StringFormat("BREAKEVEN: Ticket=%d, Nouveau SL=%.2f", ticket, request.sl));
         }
      }
      // Trailing stop
      else if(UseTrailingStop && profitPips >= TrailingStart)
      {
         double newSL = currentPrice - (TrailingStep * point);
         if(newSL > sl)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               Print("Trailing stop mis à jour: ", newSL);
               LogTrade(StringFormat("TRAILING: Ticket=%d, Nouveau SL=%.2f", ticket, newSL));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Fermeture d'une position                                         |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.deviation = Slippage;
            
            if(OrderSend(request, result))
            {
               Print("Position fermée: ", ticket);
               LogTrade(StringFormat("POSITION CLOSED: Ticket=%d", ticket));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Extraction des niveaux de trade depuis la réponse Gemini         |
//+------------------------------------------------------------------+
bool ExtractTradeLevels(string response, double &entry, double &sl, double &tp)
{
   entry = 0;
   sl = 0;
   tp = 0;
   
   // Chercher Entry
   int entryPos = StringFind(response, "Entry:");
   if(entryPos >= 0)
   {
      string entryStr = StringSubstr(response, entryPos + 6, 20);
      entry = StringToDouble(entryStr);
   }
   
   // Chercher SL
   int slPos = StringFind(response, "SL:");
   if(slPos >= 0)
   {
      string slStr = StringSubstr(response, slPos + 3, 20);
      sl = StringToDouble(slStr);
   }
   
   // Chercher TP
   int tpPos = StringFind(response, "TP:");
   if(tpPos >= 0)
   {
      string tpStr = StringSubstr(response, tpPos + 3, 20);
      tp = StringToDouble(tpStr);
   }
   
   // Alternative: chercher Stop Loss et Take Profit
   if(sl == 0)
   {
      int stopLossPos = StringFind(response, "Stop Loss");
      if(stopLossPos >= 0)
      {
         string slStr = StringSubstr(response, stopLossPos + 10, 20);
         sl = StringToDouble(slStr);
      }
   }
   
   if(tp == 0)
   {
      int takeProfitPos = StringFind(response, "Take Profit");
      if(takeProfitPos >= 0)
      {
         string tpStr = StringSubstr(response, takeProfitPos + 12, 20);
         tp = StringToDouble(tpStr);
      }
   }
   
   return (entry > 0 && sl > 0 && tp > 0);
}

//+------------------------------------------------------------------+
//| Vérifie si le pattern est VALIDE dans la réponse                 |
//+------------------------------------------------------------------+
bool IsPatternValid(string response)
{
   // Chercher des indicateurs de validité
   if(StringFind(response, "VALID") >= 0 ||
      StringFind(response, "CONFIRMED") >= 0 ||
      StringFind(response, "COMPLETE") >= 0 ||
      StringFind(response, "setup is VALID") >= 0 ||
      StringFind(response, "pattern is confirmed") >= 0)
   {
      // S'assurer que ce n'est pas "INVALID" ou "INCOMPLETE"
      if(StringFind(response, "INVALID") >= 0 || 
         StringFind(response, "INCOMPLETE") >= 0 ||
         StringFind(response, "NOT MET") >= 0)
      {
         return false;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Vérifie si le pattern est INVALIDE                               |
//+------------------------------------------------------------------+
bool IsPatternInvalid(string response)
{
   if(StringFind(response, "INVALID") >= 0 ||
      StringFind(response, "INCOMPLETE") >= 0 ||
      StringFind(response, "DO NOT ENTER") >= 0 ||
      StringFind(response, "No trade") >= 0 ||
      StringFind(response, "NOT MET") >= 0)
   {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA GEMINI SMC START - AVEC TRADING");
   Print("========================================");
   Print("Symbole: ", _Symbol);
   Print("Magic Number: ", magicNumber);
   Print("Lot size: ", LotSize);
   Print("Risk: ", RiskPercent, "%");
   Print("========================================");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Attention: Le trading automatique est desactive.");

   CallGemini();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Gérer les positions ouvertes (breakeven, trailing)
   ManagePositions();
   
   // Appeler Gemini à intervalles réguliers
   if(TimeCurrent() >= nextCallTime)
   {
      CallGemini();
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA arrêté. Raison: ", reason);
   LogTrade(StringFormat("EA STOPPED: Reason=%d", reason));
}

//+------------------------------------------------------------------+
//| Fonction existante GetData (conservée)                           |
//+------------------------------------------------------------------+
string GetData(int count)
{
   MqlRates r[]; 
   ArraySetAsSeries(r, true); 
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) 
   {
      Print("Erreur: Impossible de recuperer l'historique.");
      return "";
   }

   string s = "";
   for(int i = count - 1; i >= 0; i--)
   {
      s += "[H:" + DoubleToString(r[i].high, (int)Digits()) + 
           " L:" + DoubleToString(r[i].low, (int)Digits()) + 
           " C:" + DoubleToString(r[i].close, (int)Digits()) + "]";
      if(i > 0) s += ", ";
   }
   return s;
}

//+------------------------------------------------------------------+
//| Fonction existante Clean (conservée)                             |
//+------------------------------------------------------------------+
string Clean(string s)
{
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   return s;
}

//+------------------------------------------------------------------+
//| Fonction existante ExtractFullResponse (conservée)               |
//+------------------------------------------------------------------+
string ExtractFullResponse(string jsonResponse)
{
   string result = "";
   
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse;
   
   startPos += 9;
   
   int endPos = startPos;
   int len = StringLen(jsonResponse);
   bool inEscape = false;
   
   for(int i = startPos; i < len; i++)
   {
      ushort ch = StringGetCharacter(jsonResponse, i);
      
      if(inEscape)
      {
         inEscape = false;
         continue;
      }
      
      if(ch == '\\')
      {
         inEscape = true;
         continue;
      }
      
      if(ch == '"')
      {
         endPos = i;
         break;
      }
   }
   
   if(endPos == startPos) return jsonResponse;
   
   result = StringSubstr(jsonResponse, startPos, endPos - startPos);
   
   StringReplace(result, "\\n", "\r\n");
   StringReplace(result, "\\r", "\r");
   StringReplace(result, "\\t", "\t");
   StringReplace(result, "\\\"", "\"");
   StringReplace(result, "\\\\", "\\");
   
   return result;
}

//+------------------------------------------------------------------+
//| Fonction principale CallGemini (modifiée avec trading)           |
//+------------------------------------------------------------------+
void CallGemini()
{
   int candlesToFetch = isFirstCall ? 48 : 10; 
   string data_str = GetData(candlesToFetch);
   
   if(data_str == "") 
   {
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;
   string context = isFirstCall ? "4 hours of" : "last 10";
   
   string prompt = 
   "You are an expert SMC/ICT trader. Analyze this chronological sequence of " + context + " XAUUSD M5 candles " +
   "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
   "Look strictly for this specific setup: " +
   "1. Creation of a clear Buy Side Liquidity (BSL) swing high. " +
   "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price drops below a low but rejects/closes higher). " +
   "3. Market structure shifting upwards to target the BSL high. " +
   "If this exact pattern is confirmed and it is time to enter a LONG trade towards the BSL, return the details of your analysis and give the details of the detected conditions." +
   "And in this case give also the details of the trade with SL and TP." +
   "Format the trade details clearly with 'Entry:', 'SL:', and 'TP:' labels." +
   "If the pattern is incomplete, invalid, or bearish, return the details of the conditions that are ok and the conditions that are still needed.";
   
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   char payload_in[], payload_out[];
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();
   int res = WebRequest("POST", url, req_headers, 30000, payload_in, payload_out, res_headers);

   if(res == -1)
   {
      Print("Erreur WebRequest: ", GetLastError());
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   Print("Taille de la réponse JSON: ", StringLen(out), " caractères");
   
   string finalResponse = ExtractFullResponse(out);
   
   Print("Taille du texte extrait: ", StringLen(finalResponse), " caractères");
   
   // --- LOG DE LA RÉPONSE COMPLÈTE ---
   LogResponse(finalResponse);
   
   Print("========================================");
   Print("Reponse Gemini recue et loggee a ", TimeToString(TimeCurrent()));
   Print("Fichier: Gemini_Logs_" + GetDateString() + ".txt");
   Print("Debut de la reponse: ", StringSubstr(finalResponse, 0, 300), "...");
   Print("========================================");

   // Gestion des erreurs API
   if(res == 503 || res == 429)
   {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return; 
   }
   else if(res != 200)
   {
      Print("Erreur API Gemini fatale (Code ", res, "). Nouvel essai dans 1 minute.");
      nextCallTime = TimeCurrent() + 60;
      return; 
   }

   // --- TRADING : Vérifier si le pattern est valide ---
   if(IsPatternValid(finalResponse))
   {
      Print(">>> PATTERN VALIDE DETECTE PAR GEMINI <<<");
      
      double entry = 0, sl = 0, tp = 0;
      if(ExtractTradeLevels(finalResponse, entry, sl, tp))
      {
         Print("Niveaux extraits - Entry: ", entry, " SL: ", sl, " TP: ", tp);
         
         // Vérifier si on a déjà exécuté ce trade
         bool alreadyExecuted = false;
         if(PositionSelectByTicket(GetLastPositionTicket()))
         {
            alreadyExecuted = true;
            Print("Position déjà ouverte, on n'entre pas.");
         }
         
         if(!alreadyExecuted && CanTrade())
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            
            // Vérifier que le prix actuel est proche de l'entrée suggérée
            if(MathAbs(ask - entry) <= 50 * point)
            {
               Print("Exécution du trade LONG...");
               ExecuteLongTrade(entry, sl, tp);
            }
            else
            {
               Print("Prix actuel (", ask, ") trop éloigné de l'entrée suggérée (", entry, ")");
            }
         }
      }
      else
      {
         Print("Impossible d'extraire les niveaux de trade de la réponse Gemini");
      }
   }
   else if(IsPatternInvalid(finalResponse))
   {
      Print(">>> PATTERN INVALIDE DETECTE PAR GEMINI <<<");
      Print("Aucun trade exécuté.");
      
      // Optionnel: fermer les positions existantes si le pattern devient invalide?
      // CloseAllPositions(); // Décommenter si vous voulez fermer au signal invalide
   }
   else
   {
      Print(">>> STATUT DU PATTERN NON DETERMINE <<<");
   }

   if(isFirstCall) 
   {
      Print("Contexte initial analyse par l'IA avec succes.");
      isFirstCall = false; 
   }
   
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse dans ", IntervalMin, " minutes.");
}
