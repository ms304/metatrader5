//+------------------------------------------------------------------+
//| GEMINI SIMPLE STABLE (CODE COMPLET ET FONCTIONNEL)               |
//+------------------------------------------------------------------+
#property strict
#property version "4.00"

// --- ATTENTION: Remplacez par votre vraie clé API ---
input string API_KEY = "DIDIER LE HPI REUNIONNAIS";

input int IntervalMin = 5;

datetime lastTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA GEMINI SIMPLE START");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Attention: Le trading automatique est desactive.");

   CallGemini();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() - lastTime >= IntervalMin * 60)
   {
      CallGemini();
      lastTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
string GetData()
{
   MqlRates r [ ] ; // Espaces ajoutes pour eviter le bug d'affichage
   ArraySetAsSeries(r, true);
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, 10, r) < 10) 
   {
      Print("Erreur: Impossible de recuperer les prix.");
      return "";
   }

   string s = "";
   for(int i=0; i<10; i++)
   {
      s += DoubleToString(r[i].close, _Digits);
      if(i < 9) s += ","; // Evite la virgule finale
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
void CallGemini()
{
   string data_str = GetData();
   if(data_str == "") return;

   // Definition de l'URL et du prompt JSON
   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + API_KEY;
   string prompt = "Analyse XAUUSD closes: " + data_str + ". Return strictly one word: bullish or bearish.";
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   
   // --- ASTUCE ANTI-BUG ---
   // Declaration sur une seule ligne pour eviter la coupure du code
   char payload_in [ ] , payload_out [ ] ;
   
   // Conversion du JSON en tableau de caracteres
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   
   // CRITIQUE : Enlever le caractere nul (\0) a la fin sinon l'API Google refuse la requete (Erreur 400)
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();

   // Envoi de la requete HTTP POST
   int res = WebRequest(
      "POST",
      url,
      req_headers,
      10000,
      payload_in,
      payload_out,
      res_headers
   );

   if(res == -1)
   {
      Print("Erreur WebRequest: ", GetLastError(), ". Verifiez que l'URL est autorisee dans Outils > Options > Expert Advisors.");
      return;
   }

   // Conversion de la reponse en texte
   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   // Affiche la reponse (Vous pouvez ajouter une logique ici pour filtrer le mot exact)
   Print("GEMINI REPONSE => ", out);
}
