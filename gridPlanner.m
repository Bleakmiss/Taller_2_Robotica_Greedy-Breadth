classdef gridPlanner< dynamicprops
   	
        % GridPlanner
        % Calculates path for a given goal on a Occupancy grid map
        % Author and Copyright Daniel Barandica 2021

    properties
        %Definition of variables used in the class
        mode;
        robotRadius;
        goalRadiusTolerance;
        map;
        mapInflated;
        res;
        Size;
    end
    
    methods
        function obj = gridPlanner(mode,robotRadius,goalRadiusTolerance)
            %gridPlanner Class Constructor
            % Inputs: 
               % mode: Type of algorithm for finding path 
               % robotRadius: Radius of robot
               % goalRadiusTolerance: Radius of area where the goal is 
            
            obj.mode= mode;
            obj.robotRadius= robotRadius;
            obj.goalRadiusTolerance= goalRadiusTolerance;

        end
        
        function loadMap(obj,map_image) 
            %loadMap: Load map to the class            
            
            % Inputs:
               %map_image: it has to be a Occupancy grip map 
            
            % Assign parameters 
            obj.map = map_image; 
            obj.Size= obj.map.GridSize; %Size of Occupancy grip map 
            obj.res= obj.map.Resolution; %Resolution of Occupancy grip map 
            inflate(obj.map, obj.robotRadius); %Inflate map equals to a the robot radius
        end
        
        function [path] = plan(obj,w_xi_start_0,w_xi_goal_0,Paces)
            %plan:Calculates path from start position of the robot until goal point
            
            % Inputs:
                % w_xi_start_0: Initial pose of robot scaled to resolution  
                % w_xi_goal_0: Goal pose of robot scaled to resolution
                % Paces: Jumps of nodes that algorithm is going to do for
                % finding path
            % Outputs:
                % path: Path until goal point 
            
            goalCirc = obj.goalRadiusTolerance;
            %Define width and heigh of map
            Width= obj.Size(2);
            Heigh= obj.Size(1);
            
            %Scale of points given
            w_xi_start= w_xi_start_0*obj.res;
            w_xi_goal= w_xi_goal_0*obj.res;
            
            
            
            %Evalute that initial pose is on the map
            if w_xi_start(1,1)>Width |  w_xi_start(1,2)>Heigh 
                path= NaN;
                return;
            end
            
            %Evalute that goal pose is on the map
            if w_xi_goal(1,1)>Width |  w_xi_goal(1,2)>Heigh 
                path= NaN;
                return;
            end
            
            
            % Create an empty graph and assign the start state as the first node
            g = graph();
            g = addnode(g, table(w_xi_start(1,1),w_xi_start(1,2), -1, 'VariableNames', {'X','Y','Parent'}));
            
            % Initialize priority queue with the the start node
            h = abs(w_xi_goal(1,1) - w_xi_start(1,1)) +  abs(w_xi_goal(1,2) - w_xi_start(1,2));
            priorityTable = table(1, w_xi_start(1,1),w_xi_start(1,2), -1, h, 'VariableNames',{'Index', 'X', 'Y', 'Parent', 'h'});

            % Initialize open list with all possible nodes
            openlist = zeros(Width,Heigh);
            % Mark as visited the initial state
            openlist(w_xi_start(1,1),w_xi_start(1,2)) = 1;
            
            % Define motion commands
            % 8 directions (including diagonals)
            motionDelta = [0 -1; 1 -1; 1 0; 1 1; 0 1; -1 1; -1 0; -1 -1];
            % Select subset of 4 directions (left, up, right, down)
            motionDelta = motionDelta(1:2:end,:)*Paces; 
            for n = 1:(Width*Heigh)-1    
            % Select node to expand from queue and expand it with the motion model to
            % obtain the neighbors    
                if strcmp(obj.mode, 'breadth')
                    % In breadth is simple because we just take the nodes in order
                    % that they were added to the queue (FIFO)
                    % In this case it is equivalent to the for index
                    openedNodeInd = n;
                
                elseif strcmp(obj.mode, 'greedy')
                    % In a greedy algorithm, we pop from a priority queue the "best" 
                    % node based on the greedy heuristic
                    priorityTable = sortrows(priorityTable,{'h'},{'ascend'});
                    % Pop element
                    openedNodeInd = priorityTable.Index(1,1);
                    % Remove elelement from the priority queue
                    priorityTable(1,:) = [];       
                end   
                % Calculate neighbors applying motion model  
                neighbors = motionDelta + [g.Nodes.X(openedNodeInd) g.Nodes.Y(openedNodeInd)];

                % Trim neighbors that went outside of the map limits
                neighbors(:,1) = min(max(1,neighbors(:,1)),Width-1);
                neighbors(:,2) = min(max(1,neighbors(:,2)),Heigh-1);
                % Remove repeated neighbors (because of trimming this is possible)
                neighbors = unique(neighbors, 'rows');

                % Get the opened state of the neighbors
                openedIndices = openlist(sub2ind([Width,Heigh], neighbors(:,1), neighbors(:,2)));

                % Remove the neighbors that are in collision with the grid 
                % or were already opened (because they are already in the graph)
                obsIndex = getOccupancy(obj.map, neighbors/obj.res);
                collisionIndex = (openedIndices > 0) | obsIndex  ;
                neighbors(collisionIndex, :) = [];

                % Mark the valid neighbors as opened in the open list
                % We assign the node index with the counter of opened nodes
                numNodes = g.numnodes;
                openlist(sub2ind([Width,Heigh], neighbors(:,1), neighbors(:,2))) = numNodes+(1:size(neighbors,1));

                % Add the neighbors to the graph as new nodes
                numValidNeighbors = size(neighbors,1);
                parent = repmat(openedNodeInd, numValidNeighbors,1);    
                g = addnode(g, table(neighbors(:,1), neighbors(:,2), parent, 'VariableNames', {'X','Y', 'Parent'}));
                g = addedge(g, openedNodeInd, numNodes+(1:size(neighbors,1)));
                %Calculate heuristic and add neighbors to priority table (only for greedy, A*)
                if strcmp(obj.mode, 'greedy')
                    % Choose heuristic function: manhattan or euclidean
                    h = abs(w_xi_goal(1,1) - neighbors(:,1)) +  abs(w_xi_goal(1,2) - neighbors(:,2));
                    %h = (goalState(1,1) - neighbors(:,1)).^2 + (goalState(2,1) - neighbors(:,2)).^2;

                    % We increment the table by concatenation (this is NOT the ELEGANT WAY)
                    priorityTable = [priorityTable; ...
                                     table(numNodes+(1:numValidNeighbors)', neighbors(:,1), neighbors(:,2), parent, h,  'VariableNames', {'Index', 'X','Y', 'Parent', 'h'})];
                end      
                
                % Check if we reached the goal
                inGoal = sum(bsxfun(@minus,[g.Nodes.X g.Nodes.Y],w_xi_goal).^2,2) < (goalCirc*obj.res).^2;
                if any(inGoal)
                    % Find path to goal using function findPath
                    %print("LLEGUE")
                    path = findPath(g,w_xi_goal, goalCirc)/obj.res; %Scale path to resolution given
                    %Plot of map with the path found 
                    obj.map.show();
                    hold on;
                    plot(path(:,1),path(:,2));
                    plot(w_xi_start_0(1,1), w_xi_start_0(1,2),'o');
                    plot(w_xi_goal_0(1,1), w_xi_goal_0(1,2),'o');
                    viscircles(w_xi_goal_0,goalCirc);
                    break;
                end
            end
            function path = findPath(g, goalState, goalCirc)
                % Get goal node index
                inGoal = sum(bsxfun(@minus,[g.Nodes.X g.Nodes.Y],goalState).^2,2) < goalCirc.^2;
                nodeInd = find(inGoal);

                % Preallocate path vector with a fixed number of max points
                maxPoints = 1000;
                pathInternal = zeros(maxPoints,2);

                % Start back tracking
                for ii = 1:maxPoints
                    % Add point to path (we start from goal and then back)
                    pathInternal(ii,:) = [g.Nodes.X(nodeInd) g.Nodes.Y(nodeInd)];
                    % Get parent of node
                    nodeInd = g.Nodes.Parent(nodeInd);
                    % Check if parent is the starting state, if yes we found path
                    % if not, continue iterating
                    if nodeInd == -1
                        disp('Path found')
                        % Trim the path to the number of points (because we
                        % preallocated)
                        % And flip it vertically because we start it from the goal and
                        % back
                        path = flipud(pathInternal(1:ii,:));
                        break;
                    end
                    if ii == maxPoints
                        % If we reach this condition we didn't find the path. 
                        path= NaN;
                        break;
                    end  
                end

            end
        end
        
    end   
end 