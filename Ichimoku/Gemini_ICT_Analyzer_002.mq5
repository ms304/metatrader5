//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//+------------------------------------------------------------------+
#property strict
#property version "4.06"

input string API_KEY = "pop polopop polop pop";

input int IntervalMin = 5;

// Remplacement de lastTime par nextCallTime pour un chronometre dynamique
datetime nextCallTime = 0; 
bool isFirstCall = true;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA GEMINI SMC START");
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Attention: Le trading automatique est desactive.");

   // Au demarrage, on declenche l'appel immediatement
   CallGemini();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // On verifie si l'heure actuelle a depasse l'heure de la prochaine execution prevue
   if(TimeCurrent() >= nextCallTime)
   {
      CallGemini();
   }
}

//+------------------------------------------------------------------+
string GetData(int count)
{
   MqlRates r [ ] ; 
   ArraySetAsSeries(r, true); 
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) 
   {
      Print("Erreur: Impossible de recuperer l'historique. Nouvel essai dans 10 secondes...");
      return "";
   }

   string s = "";
   for(int i = count - 1; i >= 0; i--)
   {
      s += "[H:" + DoubleToString(r[i].high, _Digits) + 
           " L:" + DoubleToString(r[i].low, _Digits) + 
           " C:" + DoubleToString(r[i].close, _Digits) + "]";
           
      if(i > 0) s += ", ";
   }

   return s;
}

//+------------------------------------------------------------------+
string Clean(string s)
{
   StringReplace(s, "\"", "");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
}

//+------------------------------------------------------------------+
string ExtractSignal(string jsonResponse)
{
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse; 
   
   startPos += 9; 
   int endPos = StringFind(jsonResponse, "\"", startPos);
   if(endPos == -1) return jsonResponse;
   
   string signal = StringSubstr(jsonResponse, startPos, endPos - startPos);
   StringReplace(signal, "\\n", ""); 
   StringReplace(signal, "\n", "");
   
   return signal;
}

//+------------------------------------------------------------------+
void CallGemini()
{
   int candlesToFetch = isFirstCall ? 48 : 10; 
   string data_str = GetData(candlesToFetch);
   
   // Si on n'a pas pu recuperer les bougies (MT4 non connecte), on retente dans 10s
   if(data_str == "") 
   {
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + API_KEY;
   string context = isFirstCall ? "4 hours of" : "last 10";
   
   string prompt = 
   "You are an expert SMC/ICT trader. Analyze this chronological sequence of " + context + " XAUUSD M5 candles " +
   "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
   "Look strictly for this specific setup: " +
   "1. Creation of a clear Buy Side Liquidity (BSL) swing high. " +
   "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price drops below a low but rejects/closes higher). " +
   "3. Market structure shifting upwards to target the BSL high. " +
   "If this exact pattern is confirmed and it is time to enter a LONG trade towards the BSL, return strictly one word: BUY. " +
   "If the pattern is incomplete, invalid, or bearish, return strictly one word: WAIT.";
   
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   
   char payload_in [ ] , payload_out [ ] ;
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();

   int res = WebRequest("POST", url, req_headers, 10000, payload_in, payload_out, res_headers);
   
   // --- GESTION DES REPONSES ET DU CHRONOMETRE ---

   if(res == -1)
   {
      Print("Erreur locale WebRequest: ", GetLastError(), ". Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10; // On retente dans 10 secondes
      return;
   }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);

   // Erreur 503 (Surcharge) ou 429 (Trop de requetes)
   if(res == 503 || res == 429)
   {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai automatique dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10; // On retente dans 10 secondes
      return; 
   }
   // Autres erreurs API critiques (ex: Cle API perimee)
   else if(res != 200)
   {
      Print("Erreur API Gemini fatale (Code ", res, ") : ", out, ". Nouvel essai dans 1 minute pour eviter le spam.");
      nextCallTime = TimeCurrent() + 60; // On laisse reposer 1 minute pour les autres erreurs
      return; 
   }

   // SUCCES TOTAL (HTTP 200)
   if(isFirstCall) 
   {
      Print("Contexte initial de 4 Heures analyse par l'IA avec succes.");
      isFirstCall = false; 
   }

   string finalDecision = ExtractSignal(out);
   Print("DECISION SMC => ", finalDecision);
   
   // Si tout s'est bien passe, on programme la prochaine analyse selon le cycle normal (5 minutes)
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse programmee dans ", IntervalMin, " minutes.");
}
