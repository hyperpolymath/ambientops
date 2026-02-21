-- SPDX-License-Identifier: AGPL-3.0-or-later
-- PSA Client - Implementation

with Ada.Streams;
with GNAT.Sockets;   use GNAT.Sockets;
with GNAT.OS_Lib;
with Ada.Text_IO;

package body PSA_Client is

   -- JSON-like message format (simple implementation)
   -- Real implementation would use a proper JSON library

   procedure Connect (Conn : out Connection; Socket_Path : String) is
      Address : Sock_Addr_Type;
      Socket  : Socket_Type;
   begin
      -- Create Unix domain socket
      Create_Socket (Socket, Family_Unix, Socket_Stream);

      -- Set up address
      Address.Addr := Unix_Socket_Address (Socket_Path);

      -- Connect
      Connect_Socket (Socket, Address);

      Conn.Socket_FD := To_C (Socket);
      Conn.Connected := True;

   exception
      when E : others =>
         Conn.Connected := False;
         raise Connection_Error with "Failed to connect to PSA daemon";
   end Connect;

   procedure Disconnect (Conn : in out Connection) is
   begin
      if Conn.Connected then
         Close_Socket (To_Ada (Conn.Socket_FD));
         Conn.Connected := False;
         Conn.Socket_FD := -1;
      end if;
   end Disconnect;

   function Is_Connected (Conn : Connection) return Boolean is
   begin
      return Conn.Connected;
   end Is_Connected;

   -- Helper: Send command and receive response
   function Send_Command (Conn : Connection; Command : String) return String is
      Socket : constant Socket_Type := To_Ada (Conn.Socket_FD);
      Buffer : String (1 .. 65536);
      Last   : Natural;
   begin
      if not Conn.Connected then
         raise Connection_Error with "Not connected";
      end if;

      -- Send command
      String'Write (Stream (Socket, Socket), Command);

      -- Receive response
      String'Read (Stream (Socket, Socket), Buffer);
      return Buffer (1 .. Last);

   exception
      when others =>
         raise Protocol_Error with "Communication error";
   end Send_Command;

   function Get_Status (Conn : Connection) return Daemon_Status is
      Response : constant String := Send_Command (Conn, "STATUS");
      Status   : Daemon_Status;
   begin
      -- Parse JSON response (simplified)
      -- Real implementation would use proper JSON parsing
      Status.Running := True;
      Status.Paused := False;
      Status.Uptime_Secs := 0;
      Status.Rules_Count := 0;
      Status.Issues_Detected := 0;
      Status.Issues_Resolved := 0;

      return Status;
   end Get_Status;

   function Get_Health (Conn : Connection) return Health_Report is
      Response : constant String := Send_Command (Conn, "HEALTH");
      Report   : Health_Report;
   begin
      -- Parse response
      Report.Overall := Good;
      Report.Issues := null;
      Report.Timestamp := To_Unbounded_String ("");

      return Report;
   end Get_Health;

   function List_Rules (Conn : Connection) return Rule_Summary_Array_Access is
      Response : constant String := Send_Command (Conn, "LIST_RULES");
   begin
      -- Parse response
      return null;
   end List_Rules;

   function Get_Provenance (Conn : Connection; Rule_ID : String) return Unbounded_String is
      Response : constant String := Send_Command (Conn, "PROVENANCE " & Rule_ID);
   begin
      return To_Unbounded_String (Response);
   end Get_Provenance;

   function Query_SLM (Conn : Connection; Problem : String) return Query_Result is
      Response : constant String := Send_Command (Conn, "QUERY " & Problem);
      Result   : Query_Result;
   begin
      -- Parse response
      Result.Answer := To_Unbounded_String ("Parsing response...");
      Result.Confidence := 0.0;
      Result.Source := To_Unbounded_String ("pending");
      Result.Applied_Rule := Null_Unbounded_String;

      return Result;
   end Query_SLM;

   procedure Pause_Daemon (Conn : Connection) is
      Response : constant String := Send_Command (Conn, "PAUSE");
   begin
      null;
   end Pause_Daemon;

   procedure Resume_Daemon (Conn : Connection) is
      Response : constant String := Send_Command (Conn, "RESUME");
   begin
      null;
   end Resume_Daemon;

end PSA_Client;
