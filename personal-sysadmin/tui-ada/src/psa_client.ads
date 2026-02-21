-- SPDX-License-Identifier: AGPL-3.0-or-later
-- PSA Client - Unix socket communication with PSA daemon

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package PSA_Client is

   -- Connection handle to PSA daemon
   type Connection is private;

   -- Health levels matching Rust enum
   type Health_Level is (Good, Warning, Critical);

   -- Health issue record
   type Health_Issue is record
      Severity   : Health_Level;
      Category   : Unbounded_String;
      Message    : Unbounded_String;
      Suggestion : Unbounded_String;
   end record;

   type Health_Issue_Array is array (Positive range <>) of Health_Issue;
   type Health_Issue_Array_Access is access all Health_Issue_Array;

   -- Health report from daemon
   type Health_Report is record
      Overall    : Health_Level;
      Issues     : Health_Issue_Array_Access;
      Timestamp  : Unbounded_String;
   end record;

   -- Rule summary
   type Rule_Summary is record
      ID           : Unbounded_String;
      Name         : Unbounded_String;
      Enabled      : Boolean;
      Success_Rate : Float;
   end record;

   type Rule_Summary_Array is array (Positive range <>) of Rule_Summary;
   type Rule_Summary_Array_Access is access all Rule_Summary_Array;

   -- Daemon status
   type Daemon_Status is record
      Running         : Boolean;
      Paused          : Boolean;
      Uptime_Secs     : Natural;
      Rules_Count     : Natural;
      Last_Health     : Unbounded_String;
      Issues_Detected : Natural;
      Issues_Resolved : Natural;
   end record;

   -- Query result from SLM
   type Query_Result is record
      Answer       : Unbounded_String;
      Confidence   : Float;
      Source       : Unbounded_String;
      Applied_Rule : Unbounded_String;
   end record;

   -- Connection management
   procedure Connect (Conn : out Connection; Socket_Path : String);
   procedure Disconnect (Conn : in out Connection);
   function Is_Connected (Conn : Connection) return Boolean;

   -- Daemon commands
   function Get_Status (Conn : Connection) return Daemon_Status;
   function Get_Health (Conn : Connection) return Health_Report;
   function List_Rules (Conn : Connection) return Rule_Summary_Array_Access;
   function Get_Provenance (Conn : Connection; Rule_ID : String) return Unbounded_String;

   -- SLM interaction
   function Query_SLM (Conn : Connection; Problem : String) return Query_Result;

   -- Control
   procedure Pause_Daemon (Conn : Connection);
   procedure Resume_Daemon (Conn : Connection);

   -- Errors
   Connection_Error : exception;
   Protocol_Error   : exception;

private

   type Connection is record
      Socket_FD : Integer := -1;
      Connected : Boolean := False;
   end record;

end PSA_Client;
