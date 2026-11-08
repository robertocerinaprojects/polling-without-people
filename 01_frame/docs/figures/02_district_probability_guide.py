"""Build the seven-page illustrated guide to Step 02.

Run with Python 3 and Matplotlib. The PDF is saved next to this script.
Worked examples and selected observations describe the reviewed inputs.
"""

from pathlib import Path
import textwrap
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Ellipse, Rectangle
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.font_manager import FontProperties

OUT = Path(__file__).resolve().parent
W, H = 1600, 1100
plt.rcParams.update(
    {"font.family": "DejaVu Sans", "svg.fonttype": "none", "pdf.fonttype": 42}
)
C = {
    "ink": "#173349",
    "muted": "#4f6473",
    "line": "#97aab5",
    "blue": "#edf4fa",
    "edge": "#2e668a",
    "amber": "#fff1da",
    "amber_edge": "#a66a17",
    "teal": "#eaf5f2",
    "teal_edge": "#257c76",
    "red": "#99393c",
}
PAGES = []
CHECKS = []
fig = ax = None


def text(x, y, s, size=16, color=None, weight="normal", ha="left", bounds=None, **kw):
    t = ax.text(
        x,
        y,
        s,
        fontsize=size,
        color=color or C["ink"],
        fontweight=weight,
        ha=ha,
        va="top",
        linespacing=1.25,
        **kw,
    )
    CHECKS.append((t, bounds))
    return t


def wrap(s, n=66):
    return "\n".join(
        textwrap.fill(p, n, break_long_words=False, break_on_hyphens=False) if p else ""
        for p in s.split("\n")
    )


def fitwrap(s, width, size):
    prop = FontProperties(family="DejaVu Sans", size=size)
    out = []
    for para in s.split("\n"):
        line = ""
        for word in para.split():
            cand = (line + " " + word).strip()
            length = fig.canvas.get_renderer().get_text_width_height_descent(
                cand, prop, False
            )[0]
            if line and length > width:
                out.append(line)
                line = word
            else:
                line = cand
        out.append(line)
    return "\n".join(out)


def page(num, title, subtitle):
    global fig, ax, CHECKS
    CHECKS = []
    fig, ax = plt.subplots(figsize=(16, 11))
    fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
    fig.patch.set_facecolor("white")
    ax.set(xlim=(0, W), ylim=(H, 0))
    ax.axis("off")
    text(
        50,
        30,
        "DISTRICT ALLOCATION  /  " + str(num) + " OF 7",
        12,
        C["teal_edge"],
        weight="bold",
    )
    text(50, 64, title, 27, weight="bold")
    text(50, 111, subtitle, 14, C["muted"])
    ax.plot([50, 1550], [1048, 1048], lw=0.8, color=C["line"])
    text(
        50,
        1065,
        "Source: 01_frame/scripts/02_build_puma_cd_crosswalk.R  |  National run: 30 October 2026",
        10.6,
        C["muted"],
    )
    text(1550, 1065, str(num) + "/7", 11, C["muted"], ha="right")
    PAGES.append(fig)


def arrow(a, b, color=None):
    ax.add_patch(
        FancyArrowPatch(
            a,
            b,
            arrowstyle="-|>",
            mutation_scale=15,
            linewidth=1.3,
            color=color or C["line"],
        )
    )


def table(x, y, w, headers, rows, widths=None, caption="", note="", fs=13.5, rowh=33):
    headh = 56 if any("\n" in h for h in headers) else 42
    if widths is None:
        widths = [1 / len(headers)] * len(headers)
    widths = [z / sum(widths) * w for z in widths]
    if caption:
        text(x, y, caption, 12.4, C["teal_edge"], weight="bold")
        y += 30
    ax.add_patch(Rectangle((x, y), w, headh, facecolor=C["blue"], edgecolor="none"))
    xs = [x]
    for v in widths:
        xs.append(xs[-1] + v)
    for i, h in enumerate(headers):
        text(
            xs[i] + 8,
            y + 8,
            h,
            fs - 1,
            weight="bold",
            bounds=(xs[i], y, widths[i], headh),
        )
    y += headh
    for ri, row in enumerate(rows):
        if ri % 2 == 1:
            ax.add_patch(
                Rectangle((x, y), w, rowh, facecolor="#f8fafb", edgecolor="none")
            )
        for i, v in enumerate(row):
            text(xs[i] + 8, y + 8, str(v), fs, bounds=(xs[i], y, widths[i], rowh))
        ax.plot([x, x + w], [y + rowh, y + rowh], lw=0.6, color="#d5dfe4")
        y += rowh
    if note:
        text(
            x,
            y + 10,
            fitwrap(note, w - 10, 11.5),
            11.5,
            C["muted"],
            bounds=(x, y, w, 90),
        )
    return y


def node(
    y,
    h,
    title,
    body,
    headers,
    rows,
    caption,
    widths=None,
    note="",
    kind="process",
    fs=15.4,
    tablefs=13.5,
    rowh=33,
):
    x, w = 50, 650
    fill, edge = (
        (C["amber"], C["amber_edge"])
        if kind == "exception"
        else (C["teal"], C["teal_edge"]) if kind == "source" else (C["blue"], C["edge"])
    )
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0,rounding_size=8",
            facecolor=fill,
            edgecolor=edge,
            linewidth=1,
        )
    )
    text(x + 20, y + 17, title, 17, weight="bold", bounds=(x, y, w, h))
    text(x + 20, y + 53, fitwrap(body, 605, fs), fs, bounds=(x, y, w, h))
    arrow((707, y + h / 2), (741, y + h / 2), edge)
    table(755, y + 8, 795, headers, rows, widths, caption, note, tablefs, rowh)


def finish():
    fig.canvas.draw()
    ren = fig.canvas.get_renderer()
    errors = []
    for t, b in CHECKS:
        bb = t.get_window_extent(ren).transformed(ax.transData.inverted())
        xmin, xmax = bb.x0, bb.x1
        ymin, ymax = sorted([bb.y0, bb.y1])
        if xmin < 0 or xmax > W or ymin < 0 or ymax > H:
            errors.append("PAGE " + t.get_text())
        if b:
            x, y, w, h = b
            if xmin < x - 1 or xmax > x + w - 4 or ymin < y - 1 or ymax > y + h - 2:
                errors.append(
                    f"BOX {xmin:.0f},{xmax:.0f},{ymin:.0f},{ymax:.0f} vs {b}: "
                    + t.get_text()
                )
    if errors:
        raise RuntimeError("\n".join(errors))


page(
    1,
    "First, how the geographic areas fit together",
    "How 2020 Census statistical areas fit within a state and overlap a 120th Congress district. Shapes are schematic.",
)
for cx, cy, w, h, label, tx, ty, fill in [
    (450, 410, 800, 500, "STATE", 160, 195, "#f4f7f9"),
    (390, 420, 560, 370, "PUMA", 210, 260, "#e5eff7"),
    (385, 450, 365, 245, "CENSUS TRACT", 250, 338, "#d4e6ef"),
    (380, 475, 245, 140, "BLOCK GROUP", 292, 415, "#b7d8e2"),
]:
    ax.add_patch(Ellipse((cx, cy), w, h, facecolor=fill, edgecolor=C["edge"], lw=1.1))
    text(tx, ty, label, 14, weight="bold")
for bx, label in [(323, "Block A"), (450, "Block B")]:
    ax.add_patch(
        Ellipse((bx, 485), 70, 55, facecolor="white", edgecolor=C["edge"], lw=1.2)
    )
    text(bx, 475, label, 11, ha="center")
ax.add_patch(
    Ellipse((600, 420), 430, 370, facecolor="#f8dca1", alpha=0.35, edgecolor="none")
)
ax.add_patch(
    Ellipse(
        (600, 420),
        430,
        370,
        facecolor="none",
        edgecolor=C["amber_edge"],
        lw=2,
        linestyle="--",
    )
)
text(
    620,
    350,
    "CONGRESSIONAL\nDISTRICT",
    15,
    weight="bold",
    ha="center",
    color=C["amber_edge"],
)
text(90, 680, "Block A is outside the illustrated district. Block B is inside it.", 14)
text(90, 708, "A district can cut across a block group, tract and PUMA.", 14)
text(
    90,
    736,
    "The file assigns one district code per block. Census tabulates Colorado’s split block in CO-08.",
    14,
)
defs = [
    ("Block", "Smallest geographic unit used here; supplies 2020 adult counts."),
    (
        "Block group (BG)",
        "Contains blocks. This is the smallest level with our published CVAP estimates.",
    ),
    (
        "Census tract",
        "Contains block groups. The tract lookup locates blocks in 2020 PUMAs.",
    ),
    (
        "PUMA",
        "Public Use Microdata Area: a group of whole tracts. Our individual microdata identify this area, not a block group.",
    ),
    (
        "Congressional district (CD)",
        "The destination whose probability we calculate within each PUMA.",
    ),
    (
        "State",
        "Contains the PUMAs and districts. State codes are part of their unique identifiers.",
    ),
]
y = 175
for name, body in defs:
    text(910, y, name, 16.5, weight="bold")
    text(910, y + 28, wrap(body, 61), 14.5)
    y += 96
text(
    50,
    805,
    "County, county equivalent and town: a second set of boundaries",
    18,
    weight="bold",
)
text(
    50,
    846,
    wrap(
        "Tracts also belong to counties or county equivalents. A PUMA can cross county boundaries, so county does not sit between PUMA and state in the nesting above. In Connecticut, newer ACS identifiers use nine planning regions as county equivalents instead of the eight old counties.",
        137,
    ),
    14.5,
)
text(
    50,
    920,
    wrap(
        "Connecticut towns (county subdivisions) appear only in the relationship file that helps connect old block groups to new planning-region identifiers. They are not an additional level at which we allocate people. The Connecticut conversion is explained on panel 3.",
        137,
    ),
    14.5,
)
text(
    50,
    995,
    "CVAP = citizen voting-age population: citizens aged 18+.  ACS = American Community Survey.",
    14,
    weight="bold",
)
finish()

page(
    2,
    "Four inputs answer four different questions",
    "Read leading zeros as part of an identifier. ACTUAL rows are verified examples; ILLUSTRATIVE rows explain the calculation.",
)
node(
    155,
    175,
    "A  Which district contains each block?",
    "Census BEF means Block Equivalency File. It assigns original 2020 blocks to the pinned 120th Congress district plan. CDFP is the district code. ZZ means no district is assigned; it does not itself mean zero population.",
    ["GEOID", "STATEFP", "CDFP"],
    [
        ["010010201001000", "01", "06"],
        ["010010201001001", "01", "06"],
        ["010010201001002", "01", "06"],
    ],
    "ACTUAL: first three rows of NationalCD120.txt",
    [0.58, 0.22, 0.20],
    kind="source",
    fs=14.5,
)
node(
    355,
    175,
    "B  Which PUMA contains each tract?",
    "The Census tract-to-PUMA table supplies PUMA5CE. A block GEOID begins with state + county + tract, so its first 11 digits identify the tract. Combine STATEFP with PUMA5CE to identify a PUMA uniquely.",
    ["STATEFP", "COUNTYFP", "TRACTCE", "PUMA5CE"],
    [
        ["01", "001", "020100", "01700"],
        ["01", "001", "020200", "01700"],
        ["01", "001", "020300", "01700"],
    ],
    "ACTUAL: 2020 Census tract-to-PUMA lookup",
    kind="source",
    fs=14.5,
)
node(
    555,
    190,
    "C  How many adults lived in each block?",
    "PL stands for Public Law: P.L. 94-171 is the law behind this Census redistricting data release. P0030001 counts adults aged 18+, including noncitizens. POP100 counts residents of all ages. The code calls these vap20 and pop20.",
    ["GEOID", "POP100\n→ pop20", "P0030001\n→ vap20"],
    [["b1", "90", "60"], ["b2", "210", "140"], ["b3", "150", "100"]],
    "ILLUSTRATIVE: invented blocks b1–b3, after population matching",
    [0.30, 0.35, 0.35],
    "",
    kind="source",
    fs=14.5,
)
node(
    770,
    175,
    "D  How many citizen adults are estimated?",
    "The 2020–2024 ACS CVAP table supplies one Total estimate per block group. We use lnnumber = 1. This is a survey estimate for the block group; citizen-adult counts are not observed for individual blocks.",
    ["geoid / bg_cvap", "lnnumber", "lntitle", "cvap_est"],
    [
        ["G1", "1", "Total", "120"],
        ["G2", "1", "Total", "80"],
        ["G3", "1", "Total", "100"],
    ],
    "ILLUSTRATIVE: three block groups used in panels 3, 5 and 7",
    [0.33, 0.21, 0.21, 0.25],
    kind="source",
    fs=14.5,
)
text(
    50,
    978,
    "The all-age counts check the joins: block sums match state totals; no population is lost or duplicated;",
    14,
)
text(
    50,
    1006,
    "adult counts lie between zero and all-age counts. The allocation denominator uses adults, not all ages.",
    14,
    weight="bold",
)
finish()

page(
    3,
    "Join the geography, then attach one CVAP estimate",
    "A + B + C → block-group/PUMA/district portions → reconcile Connecticut IDs → attach CVAP from D.",
)
node(
    155,
    200,
    "Combine A, B and C into portions",
    "Join blocks to PUMAs and district codes, then add adult counts within each block-group / PUMA / district combination. “Coverage” means which places the records map to; it does not mean a survey response rate. Matching checks ask whether every identifier finds the required row.",
    ["bg_2020", "PUMA5CE", "CDFP", "vap20"],
    [["G1", "P1", "D1", "60"], ["G1", "P1", "D2", "140"], ["G2", "P1", "D1", "100"]],
    "ILLUSTRATIVE: three rows of bg_2020_cells",
    note="G1, G2, P1, D1 and D2 are invented identifiers, not real Census codes.",
    fs=14.5,
)
node(
    385,
    300,
    "Connecticut: translate identifiers carefully",
    "Old block group 090093431011 overlaps two newer planning regions. One overlap covers 3,606,413 m²; the other covers 160 m². Replacing the county part of its identifier produces the two candidates shown.\n\nThe Census 2024 block-group geographic data contain the first ID, but not the second. We map the whole old group to the first ID and keep every original block. This is a specific boundary approximation, not a rule that always chooses the largest area.",
    ["bg_2020", "candidate bg_cvap", "land_m2", "ID returned?"],
    [
        ["090093431011", "091403431011", "3,606,413", "Yes"],
        ["090093431011", "091703431011", "160", "No"],
    ],
    "ACTUAL: reviewed relationship and identifier-query results",
    [0.26, 0.29, 0.20, 0.25],
    "The query uses Census TIGERweb’s “Census Block Groups” geographic layer, dated 1 January 2024. It returns identifiers and area attributes, not CVAP counts.",
    kind="exception",
    fs=14.3,
    tablefs=12.3,
)
node(
    715,
    215,
    "One group estimate must be counted once",
    "After Connecticut reconciliation, attach the published estimate to each group. G1 appears in two district rows, so its source value 120 repeats after the join. Those repeated values are the same estimate, not two populations. We split 120 into 36 + 84 on panel 5; we never count 120 + 120 = 240.",
    ["bg_cvap", "CDFP", "vap20", "repeated\ncvap_est"],
    [["G1", "D1", "60", "120"], ["G1", "D2", "140", "120"], ["G2", "D1", "100", "80"]],
    "ILLUSTRATIVE: temporary joined rows, before contributions",
    note="The exported contribution table stores the allocated amounts instead of repeated source totals.",
    fs=14.5,
)
arrow((375, 356), (375, 383))
arrow((375, 686), (375, 713))
text(
    50,
    967,
    "Outside Connecticut, the block-group identifiers match directly, apart from the 39 missing New York CVAP records.",
    14,
)
text(
    50,
    996,
    "Some Connecticut water links describe possible locations rather than an exact partition. Their 2020 population is zero.",
    14,
)
finish()

page(
    4,
    "Check matches and missing values before allocating",
    "Apply the first matching condition. These are conditions on a block group, not successive transformations of every row.",
)
node(
    155,
    215,
    "1  A CVAP group has no matching geography",
    "The CVAP table contains a block-group ID, but our reconciled block table has no matching blocks or PUMA–district portions for it. The run ends with an error for review: it cannot locate this population. No such unresolved case remained in the validated run.",
    ["bg_cvap", "cvap_est", "intersections", "result"],
    [["G_missing", "120", "NA", "Error"], ["G_matched", "120", "2", "Continue"]],
    "ILLUSTRATIVE: a failed and a successful geographic match",
    [0.29, 0.20, 0.23, 0.28],
    kind="exception",
    fs=14.5,
)
node(
    405,
    260,
    "2  The geography exists, but CVAP is missing",
    "Keep missing CVAP as NA, never zero. The 39 reviewed New York omissions match the Census suppression list. Their two PUMAs lie entirely in NY-02, so geographic containment can still give a district probability of one.\n\nIf the missing-ID set differs from those 39 reviewed IDs, the run ends with an error for investigation.",
    ["bg_cvap", "cvap_est", "reviewed\nomission?", "contribution"],
    [["NY_example", "NA", "Yes", "NA"], ["New_example", "NA", "No", "Run errors"]],
    "ILLUSTRATIVE IDs: allowed versus unreviewed missing CVAP",
    [0.28, 0.20, 0.25, 0.27],
    kind="exception",
    fs=14.5,
)
node(
    680,
    210,
    "3  The published CVAP estimate is zero",
    "All mapped portions receive a contribution of zero because there is no estimated CVAP to distribute. The source estimate is not changed. This rule covered 1,798 block groups. A published estimate of zero is still an estimate, not proof that no citizen adult lives there.",
    ["bg_cvap", "CDFP", "cvap_est", "cvap_contribution"],
    [["G_zero", "D1", "0", "0"], ["G_zero", "D2", "0", "0"]],
    "ILLUSTRATIVE: one zero-estimate group spanning two districts",
    [0.24, 0.17, 0.21, 0.38],
    fs=14.5,
)
text(50, 938, "What “stop” means in practice", 17, weight="bold", color=C["red"])
text(
    50,
    974,
    "The code raises an error and does not reach the final crosswalk save for that run. Review the named audit file,",
    14,
)
text(
    50,
    1003,
    "resolve the mismatch or document a new decision, then rerun. Files saved by an earlier successful run may still exist.",
    14,
)
finish()

page(
    5,
    "Turn each usable block-group total into contributions",
    "A contribution is an estimated number of citizen adults attributed to a PUMA–district portion; it is not yet a probability.",
)
node(
    155,
    200,
    "4  All mapped blocks have district code ZZ",
    "There is no assigned district to receive the estimate. The Connecticut water group has one published CVAP estimate of 5, although it is linked to two old block groups and two PUMAs. Keep the published 5 in the audit and record 5 as excluded once; both portion contributions are zero.",
    ["bg_cvap", "PUMA5CE", "CDFP", "cvap_contribution"],
    [["091309901000", "20500", "ZZ", "0"], ["091309901000", "20401", "ZZ", "0"]],
    "ACTUAL: the reviewed Connecticut water group",
    [0.31, 0.21, 0.15, 0.33],
    note="ZZ means “no district assigned”. It is a location code, not a population value.",
    kind="exception",
    fs=14.5,
)
node(
    385,
    235,
    "5  The group lies in one assigned portion",
    "The entire estimate goes to that PUMA and district; no population split is needed. This applied to 231,665 block groups.\n\nConnecticut group 091902114003 has CVAP 5. Both original blocks are in PUMA 20904 and CT-05, so all 5 contribute there despite the zero 2020 adult count.",
    ["bg_cvap", "PUMA5CE", "CDFP", "cvap_est", "contribution"],
    [
        ["091902114003", "20904", "05", "5", "5"],
        ["G2", "P1", "D1", "80", "80"],
        ["G3", "P1", "D2", "100", "100"],
    ],
    "First row ACTUAL; G2 and G3 are ILLUSTRATIVE",
    [0.31, 0.18, 0.12, 0.17, 0.22],
    fs=14.5,
    tablefs=12.7,
)
node(
    640,
    245,
    "6  Split the estimate using adult shares",
    "If the group spans portions, has a positive 2020 adult total, and no adults in ZZ portions, distribute its CVAP estimate in proportion to those adult counts.\n\nG1 has 200 adults in 2020: 60 in D1 and 140 in D2. Its CVAP estimate is 120. We attribute 120 × 60/200 = 36 to D1 and 120 × 140/200 = 84 to D2. The pieces add back to 120. This rule covered 6,273 groups.",
    ["bg_cvap", "CDFP", "vap20", "adult share", "contribution"],
    [
        ["G1", "D1", "60", "60 / 200", "36"],
        ["G1", "D2", "140", "140 / 200", "84"],
        ["Total", "—", "200", "1", "120"],
    ],
    "ILLUSTRATIVE: one group divided across two district portions",
    [0.20, 0.12, 0.16, 0.25, 0.27],
    fs=14.5,
    tablefs=12.8,
)
text(50, 923, "The approximation in rule 6", 17, weight="bold", color=C["amber_edge"])
text(
    50,
    961,
    "Within a block group, we assume citizen adults follow the same spatial proportions as all adults counted in 2020.",
    14,
)
text(
    50,
    991,
    "We sum block adult counts into portions first. No observed block-level CVAP counts are available or created.",
    14,
)
finish()

page(
    6,
    "The reviewed zero overrides: same arithmetic, different evidence",
    "For five groups, geography alone and 2020 adult counts both leave the split across districts unknown.",
)
node(
    155,
    260,
    "7  Five reviewed groups cannot be split",
    "These groups span several assigned districts but have zero 2020 population and adults. Rule 6 cannot split their positive CVAP estimates: its denominator is zero.\n\nOur agreed decision sets only these five allocation inputs to zero, reducing the amount allocated by 24. The published estimates stay unchanged. This is a project assumption, not a Census correction or proof of true zero population.",
    ["bg_cvap", "cvap_est", "vap20", "allocation input"],
    [
        ["060379800031", "5", "0", "0"],
        ["120219900000", "4", "0", "0"],
        ["120719800001", "5", "0", "0"],
        ["120869806001", "5", "0", "0"],
        ["120999900000", "5", "0", "0"],
    ],
    "ACTUAL: the complete list of approved overrides",
    [0.35, 0.20, 0.17, 0.28],
    kind="exception",
    fs=14.4,
    tablefs=12.8,
    rowh=30,
)
node(
    450,
    225,
    "All three zero-input routes already converge",
    "The code already uses the same calculation in all three cases: contribution = 0.\n\nRule 3 starts with a published zero. Rule 7 adjusts a positive estimate. Rule 4 excludes a positive estimate because no district is assigned. The separate labels preserve why the input is zero; the arithmetic is identical.",
    ["Reason", "Published", "Adjustment", "Excluded", "Input"],
    [
        ["Published zero", "0", "0", "0", "0"],
        ["Five overrides", "24", "24", "0", "0"],
        ["CT water exclusion", "5", "0", "5", "0"],
    ],
    "ACTUAL totals by reason; Input = Published − Adjustment − Excluded",
    [0.34, 0.17, 0.19, 0.17, 0.13],
    "Display headings abbreviate cvap_est, cvap_structural_zero_adjustment, cvap_geographic_exclusion and cvap_for_allocation.",
    fs=14.5,
    tablefs=12.3,
)
node(
    710,
    240,
    "How the rule works at a zero denominator",
    "The sequence is: allocate directly when geography fixes the destination; otherwise use adult shares if possible; otherwise review. Setting all zero-adult cases to zero CVAP would also remove Connecticut’s retained land estimate of 5.\nNew unresolved cases end the run. The five overrides apply only if their checked data still match.",
    ["Positive CVAP; 2020 adults = 0", "Decision"],
    [
        ["One assigned portion", "Allocate all directly"],
        ["Several assigned portions", "Review; five approved zeros"],
        ["Only unassigned portions", "Exclude; retain source"],
    ],
    "Decision summary: geography determines what can be done",
    [0.52, 0.48],
    fs=14.5,
    tablefs=12.8,
    rowh=34,
)
text(
    50,
    973,
    "A previously unseen exception ends the run. The allocation decision record identifies all five approved overrides.",
    14,
    weight="bold",
)
text(
    50,
    1002,
    "Known published CVAP: 240,785,129 = 240,785,100 contributed + 24 adjustment + 5 exclusion. NY unknowns are omitted.",
    13.6,
)
finish()

page(
    7,
    "Add the contributions, then calculate district probabilities",
    "The final result has one row per state / PUMA / assigned district, with a probability between zero and one.",
)
node(
    155,
    175,
    "Add citizen-adult contributions within a PUMA",
    "For each district, add contributions from all block groups in the PUMA. In our example, D1 receives 36 + 80 = 116 and D2 receives 84 + 100 = 184. The PUMA total is 300. If any contribution is unknown, its complete total stays unknown.",
    ["PUMA5CE", "CDFP", "district_cvap", "puma_cvap"],
    [["P1", "D1", "116", "300"], ["P1", "D2", "184", "300"]],
    "ILLUSTRATIVE: totals from G1, G2 and G3",
    [0.23, 0.17, 0.30, 0.30],
    fs=14.5,
)
node(
    355,
    185,
    "FIRST: is the whole PUMA in one district?",
    "Check every original block, including zero-population blocks. If all have the same assigned district and none has code ZZ, give that district probability 1. This handles 1,110 PUMAs, including the two NY PUMAs with suppressed CVAP. Their unknown population totals remain unknown.",
    ["STATEFP", "PUMA5CE", "CDFP", "puma_cvap", "allocation_weight"],
    [["36", "03310", "02", "NA", "1"], ["36", "03313", "02", "NA", "1"]],
    "ACTUAL: New York containment results",
    [0.17, 0.21, 0.13, 0.21, 0.28],
    kind="exception",
    fs=14.5,
    tablefs=12.7,
)
node(
    565,
    195,
    "OTHERWISE: divide by a complete PUMA total",
    "Require no missing contributions and a finite, positive PUMA total. Divide each district total by that PUMA total. This handles 1,352 PUMAs. If the required total is missing or nonpositive, the run errors for review.\nHere: P(D1 | P1) = 116/300; P(D2 | P1) = 184/300.",
    ["PUMA5CE", "CDFP", "district_cvap", "allocation_weight"],
    [["P1", "D1", "116", "0.386667"], ["P1", "D2", "184", "0.613333"]],
    "ILLUSTRATIVE: probabilities rounded here only for display",
    [0.23, 0.17, 0.27, 0.33],
    fs=14.4,
)
node(
    785,
    180,
    "Save the checked probability table",
    "Each state–PUMA–district key must be unique. Probabilities must lie from 0 to 1 and sum to 1 within each PUMA, allowing a numerical tolerance of 10⁻¹². Keep zero-weight intersections; remove ZZ from the final table. The output is puma_cd_crosswalk.rds.",
    ["STATEFP", "PUMA5CE", "CDFP", "allocation_\nweight", "weight_method"],
    [
        ["36", "03310", "02", "1", "structural_single_district"],
        ["36", "03313", "02", "1", "structural_single_district"],
    ],
    "ACTUAL: two rows of the saved crosswalk",
    [0.15, 0.16, 0.10, 0.22, 0.37],
    note="Full table: 2,462 PUMAs; 435 House districts + DC; 4,183 rows, including 109 zero weights.",
    fs=14.4,
    tablefs=11.8,
)
text(
    50,
    995,
    "These are PUMA-level probabilities. Every person in the same PUMA receives the same distribution when it is applied.",
    14,
    weight="bold",
)
finish()

with PdfPages(OUT / "02_district_probability_guide.pdf") as pdf:
    pdf.infodict().update(
        {
            "Title": "District probability construction: geography, data and decisions",
            "Subject": "2026 district probabilities on the pinned 2020 block geography. Worked examples and observed records.",
            "CreationDate": None,
            "ModDate": None,
        }
    )
    for f in PAGES:
        pdf.savefig(f, facecolor="white")
        plt.close(f)
