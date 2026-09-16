// SPDX-License-Identifier: Apache-2.0

unit Reverse.Graph;

interface

uses Reverse.Domain, System.SysUtils, System.Generics.Collections;

type
  TReverseGraph = class
  private
    FByUsed: TObjectDictionary<string, TList<TDependency>>;
    FNames: TDictionary<string, string>;
    FSeenEdges: TDictionary<string, Boolean>;
    function GetConsumers(const Used: string): TList<TDependency>;
    function NodeText(const Node: string): string;
    function PathText(const Nodes: TList<string>): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Edge: TDependency);
    function Reachable(const Target: string): TArray<TDependency>;
    function Paths(const Target, ProgramName: string;
      MaxPaths: Integer = 10000): TArray<string>;
    function ClassifiedPaths(const Target, ProgramName: string;
      const SourceOrigins: TDictionary<string, TSourceOrigin>;
      MaxPaths: Integer = 10000): TArray<TRoutePath>;
    property Consumers[const Used: string]: TList<TDependency> read GetConsumers;
  end;

implementation

uses System.StrUtils;

constructor TReverseGraph.Create;
begin
  inherited;
  FByUsed := TObjectDictionary<string, TList<TDependency>>.Create([doOwnsValues]);
  FNames := TDictionary<string, string>.Create;
  FSeenEdges := TDictionary<string, Boolean>.Create;
end;

destructor TReverseGraph.Destroy;
begin
  FNames.Free;
  FSeenEdges.Free;
  FByUsed.Free;
  inherited;
end;

function TReverseGraph.GetConsumers(const Used: string): TList<TDependency>;
begin
  if not FByUsed.TryGetValue(Key(Used), Result) then Result := nil;
end;

function TReverseGraph.NodeText(const Node: string): string;
begin
  if not FNames.TryGetValue(Key(Node), Result) then Result := Node;
end;

function TReverseGraph.PathText(const Nodes: TList<string>): string;
var
  Node: string;
begin
  Result := '';
  for Node in Nodes do
  begin
    if Result <> '' then Result := Result + ' -> ';
    Result := Result + NodeText(Node);
  end;
end;

procedure TReverseGraph.Add(const Edge: TDependency);
var
  List: TList<TDependency>;
  UsedKey, ConsumerKey, Identity: string;
begin
  Identity := DependencyIdentity(Edge);
  if FSeenEdges.ContainsKey(Identity) then Exit;
  FSeenEdges.Add(Identity, True);
  if Edge.UsedPath <> '' then
  begin
    UsedKey := Key(Edge.UsedPath);
    if Edge.ConsumerPath <> '' then ConsumerKey := Key(Edge.ConsumerPath)
    else ConsumerKey := Key(Edge.SourceFile);
  end
  else
  begin
    UsedKey := Key(Edge.UsedName);
    ConsumerKey := Key(Edge.Consumer);
  end;
  if not FByUsed.TryGetValue(UsedKey, List) then
  begin
    List := TList<TDependency>.Create;
    FByUsed.Add(UsedKey, List);
  end;
  List.Add(Edge);
  FNames.AddOrSetValue(UsedKey, Edge.UsedName);
  FNames.AddOrSetValue(ConsumerKey, Edge.Consumer);
end;

function TReverseGraph.Reachable(const Target: string): TArray<TDependency>;
var
  Queue: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  Output: TList<TDependency>;
  Current, Next: string;
  Edge: TDependency;
  Edges: TList<TDependency>;
begin
  Queue := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Output := TList<TDependency>.Create;
  try
    Queue.Enqueue(Key(Target));
    Seen.Add(Key(Target), True);
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      Edges := GetConsumers(Current);
      if Edges = nil then Continue;
      for Edge in Edges do
      begin
        Output.Add(Edge);
        if Edge.UsedPath <> '' then
        begin
          if Edge.ConsumerPath <> '' then Next := Key(Edge.ConsumerPath)
          else Next := Key(Edge.SourceFile);
        end
        else Next := Key(Edge.Consumer);
        if not Seen.ContainsKey(Next) then
        begin
          Seen.Add(Next, True);
          Queue.Enqueue(Next);
        end;
      end;
    end;
    Result := Output.ToArray;
  finally
    Output.Free;
    Seen.Free;
    Queue.Free;
  end;
end;

function TReverseGraph.Paths(const Target, ProgramName: string;
  MaxPaths: Integer): TArray<string>;
type
  TFrame = record
    Name: string;
    NextEdge: Integer;
  end;
var
  Output: TList<string>;
  Stack: TList<string>;
  Frames: TList<TFrame>;
  Stopped: Boolean;
  Frame, ChildFrame: TFrame;
  Edges: TList<TDependency>;
  Next: string;
begin
  if MaxPaths < 1 then raise Exception.Create('MaxPaths must be positive');
  Output := TList<string>.Create;
  Stack := TList<string>.Create;
  Frames := TList<TFrame>.Create;
  try
    Stopped := False;
    Stack.Add(Key(Target));
    Frame.Name := Key(Target);
    Frame.NextEdge := 0;
    Frames.Add(Frame);
    while (Frames.Count > 0) and not Stopped do
    begin
      Frame := Frames[Frames.Count - 1];
      if SameText(Frame.Name, ProgramName) then
      begin
        Output.Add(PathText(Stack) + ' [DPR]');
        Stopped := Output.Count >= MaxPaths;
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Edges := GetConsumers(Frame.Name);
      if (Edges = nil) or (Edges.Count = 0) then
      begin
        Output.Add(PathText(Stack) + ' [NO CONSUMER]');
        Stopped := Output.Count >= MaxPaths;
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      if Frame.NextEdge >= Edges.Count then
      begin
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      if Edges[Frame.NextEdge].UsedPath <> '' then
      begin
        if Edges[Frame.NextEdge].ConsumerPath <> '' then
          Next := Key(Edges[Frame.NextEdge].ConsumerPath)
        else Next := Key(Edges[Frame.NextEdge].SourceFile);
      end
      else Next := Key(Edges[Frame.NextEdge].Consumer);
      Inc(Frame.NextEdge);
      Frames[Frames.Count - 1] := Frame;
      if Stack.Contains(Next) then
      begin
        Output.Add(PathText(Stack) + ' -> ' + NodeText(Next) + ' [CYCLE]');
        Stopped := Output.Count >= MaxPaths;
        Continue;
      end;
      ChildFrame.Name := Next;
      ChildFrame.NextEdge := 0;
      Frames.Add(ChildFrame);
      Stack.Add(Next);
    end;
    if Stopped then Output.Add('[PATH LIST LIMITED; GRAPH RETAINS ALL REACHABLE EDGES]');
    Result := Output.ToArray;
  finally
    Frames.Free;
    Stack.Free;
    Output.Free;
  end;
end;

function TReverseGraph.ClassifiedPaths(const Target, ProgramName: string;
  const SourceOrigins: TDictionary<string, TSourceOrigin>;
  MaxPaths: Integer): TArray<TRoutePath>;
type
  TFrame = record
    Name: string;
    NextEdge: Integer;
  end;
var
  Output: TList<TRoutePath>;
  Stack: TList<string>;
  Frames: TList<TFrame>;
  Stopped: Boolean;
  Frame, ChildFrame: TFrame;
  Edges: TList<TDependency>;
  Next: string;
  Route: TRoutePath;
  Origin: TSourceOrigin;
  procedure AddRoute(const Destination: TRouteDestination;
    const TerminalPath, Text: string);
  begin
    Route.Destination := Destination;
    Route.TerminalPath := TerminalPath;
    Route.IsLimitMarker := False;
    Route.Text := Text + ' [' + RouteDestinationName(Destination) + ']';
    Output.Add(Route);
    Stopped := Output.Count >= MaxPaths;
  end;
begin
  if MaxPaths < 1 then raise Exception.Create('MaxPaths must be positive');
  if SourceOrigins = nil then
    raise Exception.Create('Source origins are required');
  Output := TList<TRoutePath>.Create;
  Stack := TList<string>.Create;
  Frames := TList<TFrame>.Create;
  try
    Stopped := False;
    Stack.Add(Key(Target));
    Frame.Name := Key(Target);
    Frame.NextEdge := 0;
    Frames.Add(Frame);
    while (Frames.Count > 0) and not Stopped do
    begin
      Frame := Frames[Frames.Count - 1];
      if SameText(Frame.Name, ProgramName) then
      begin
        AddRoute(rdDpr, Frame.Name, PathText(Stack));
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Edges := GetConsumers(Frame.Name);
      if (Edges = nil) or (Edges.Count = 0) then
      begin
        if SameText(Frame.Name, Target) then
          AddRoute(rdNoConsumer, Frame.Name, PathText(Stack))
        else if not SourceOrigins.TryGetValue(Key(Frame.Name), Origin) then
          AddRoute(rdNoConsumer, Frame.Name, PathText(Stack))
        else if Origin in [soProject, soProjectReference] then
          AddRoute(rdProjectFile, Frame.Name, PathText(Stack))
        else if Origin = soUnknown then
          AddRoute(rdNoConsumer, Frame.Name, PathText(Stack))
        else
          AddRoute(rdLibraryRoot, Frame.Name, PathText(Stack));
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      if Frame.NextEdge >= Edges.Count then
      begin
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      if Edges[Frame.NextEdge].UsedPath <> '' then
      begin
        if Edges[Frame.NextEdge].ConsumerPath <> '' then
          Next := Key(Edges[Frame.NextEdge].ConsumerPath)
        else Next := Key(Edges[Frame.NextEdge].SourceFile);
      end
      else Next := Key(Edges[Frame.NextEdge].Consumer);
      Inc(Frame.NextEdge);
      Frames[Frames.Count - 1] := Frame;
      if Stack.Contains(Next) then
      begin
        AddRoute(rdCycle, Next, PathText(Stack) + ' -> ' + NodeText(Next));
        Continue;
      end;
      ChildFrame.Name := Next;
      ChildFrame.NextEdge := 0;
      Frames.Add(ChildFrame);
      Stack.Add(Next);
    end;
    if Stopped then
    begin
      Route := Default(TRoutePath);
      Route.Text := '[PATH LIST LIMITED; GRAPH RETAINS ALL REACHABLE EDGES]';
      Route.IsLimitMarker := True;
      Output.Add(Route);
    end;
    Result := Output.ToArray;
  finally
    Frames.Free;
    Stack.Free;
    Output.Free;
  end;
end;

end.
