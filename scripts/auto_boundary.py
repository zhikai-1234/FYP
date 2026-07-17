#!/usr/bin/env python
import rospy
from geometry_msgs.msg import PointStamped
from nav_msgs.msg import OccupancyGrid

rospy.init_node('auto_boundary')
pub = rospy.Publisher('/clicked_point', PointStamped, queue_size=10)

# House is ~14.5 x 14.6 m. We size the boundary to that, but CENTER it on
# wherever the merged map's explored content actually sits (handles the merge
# offset without touching the repo).
HOUSE_HALF_X = 8.0   # half-width  + margin
HOUSE_HALF_Y = 8.0   # half-height + margin

print("Waiting for merged map...")
m = rospy.wait_for_message('/map_merge/map', OccupancyGrid, timeout=120)
map_frame = m.header.frame_id
w, h, res = m.info.width, m.info.height, m.info.resolution
ox, oy = m.info.origin.position.x, m.info.origin.position.y

# Find where the explored (known) content actually is in the merged map.
xs = []; ys = []
free_cells = []
for i, c in enumerate(m.data):
    if c != -1:                      # known (free or occupied)
        col = i % w; row = i // w
        x = ox + col * res; y = oy + row * res
        xs.append(x); ys.append(y)
        if 0 <= c < 50:              # free -> candidate seed
            free_cells.append((x, y))

if not xs:
    print("No known cells yet; is exploration running? Falling back to origin.")
    cx = cy = 0.0
else:
    cx = (min(xs) + max(xs)) / 2.0   # center of explored content
    cy = (min(ys) + max(ys)) / 2.0
    print("Explored content center: ({:.2f}, {:.2f})".format(cx, cy))

# Boundary = house-sized box centered on the explored content.
X_MIN = cx - HOUSE_HALF_X
X_MAX = cx + HOUSE_HALF_X
Y_MIN = cy - HOUSE_HALF_Y
Y_MAX = cy + HOUSE_HALF_Y

# 5th point = free cell nearest the content center (guaranteed on free space).
if free_cells:
    start_x, start_y = min(free_cells,
                           key=lambda p: (p[0]-cx)**2 + (p[1]-cy)**2)
else:
    start_x, start_y = cx, cy
print("Frame: {}".format(map_frame))
print("Boundary: X {:.2f}..{:.2f}  Y {:.2f}..{:.2f}".format(X_MIN, X_MAX, Y_MIN, Y_MAX))
print("Start point (5th): ({:.2f}, {:.2f})".format(start_x, start_y))

print("Waiting for subscribers to connect...")
rospy.sleep(5)
print("Connected to {} subscribers".format(pub.get_num_connections()))

def send(x, y, label):
    msg = PointStamped()
    msg.header.frame_id = map_frame
    msg.header.stamp = rospy.Time.now()
    msg.point.x = x; msg.point.y = y; msg.point.z = 0.0
    pub.publish(msg)
    print("Published {}: x={:.2f}, y={:.2f}".format(label, x, y))

corners = [(X_MIN, Y_MAX), (X_MAX, Y_MAX), (X_MAX, Y_MIN), (X_MIN, Y_MIN)]
print("Publishing 4 boundary corners...")
for i, (x, y) in enumerate(corners):
    rospy.sleep(8)
    send(x, y, "corner {}/4".format(i + 1))

print("Letting frontiers accumulate before start point...")
rospy.sleep(20)
send(start_x, start_y, "START point (5th)")

print("All points published! Keeping node alive...")
rospy.spin()
