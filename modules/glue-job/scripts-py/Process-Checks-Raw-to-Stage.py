import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import col, sum as _sum, to_date, date_format


# Get job parameters
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SOURCE_BUCKET",
    "SOURCE_PREFIX",
    "TARGET_BUCKET",
    "TARGET_PREFIX",
])

# Initialize contexts
sc = SparkContext()

glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)


# Try to get it from the Glue context
print("=" * 50)
print(f"Job object: {job}")
print(f"Job attributes: {dir(job)}")

# Check if it's stored in the job object
if hasattr(job, 'job_run_id'):
    print(f"Job run ID: {job.job_run_id}")
    
# Also check SparkContext app ID (alternative unique identifier)
print(f"Spark Application ID: {sc.applicationId}")
print("=" * 50)

# Construct S3 paths
source_path = f"s3://{args['SOURCE_BUCKET']}/{args['SOURCE_PREFIX']}"
target_path = f"s3://{args['TARGET_BUCKET']}/{args['TARGET_PREFIX']}"


print(f"Reading data from: {source_path}")

# Read data from raw bucket
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": [source_path],
        "recurse": True,
    },
    format="csv",
    format_options={
        "withHeader": True,
        "separator": ",",
    },

    transformation_ctx="datasource"  # ← Enables Bookmarking to prevent loading of files that have already been processed.
)

print(f"Record count (raw): {datasource.count()}")

# Convert to Spark DataFrame
df = datasource.toDF()

# Aggregate by LOCATION_ID and DATE
aggregated_df = (
    df.groupBy("LOCATION_ID", "DATE")
    .agg(
        _sum(col("SALES").cast("double")).alias("SALES"),
        _sum(col("ITEM_COUNT").cast("bigint")).alias("ITEM_COUNT"),
    )
)

print("Reformatting DATE column to yyyy-MM-dd...")

aggregated_df = aggregated_df.withColumn(
    "DATE",
    date_format(
        to_date(col("DATE"), "MM-dd-yyyy"),  # parse incoming string
        "yyyy-MM-dd"                          # output format
    )
)

print("File Contents Aggregated.")

# Select specific columns in a consistent order
aggregated_df = aggregated_df.select(
    "LOCATION_ID",
    "DATE",
    "SALES",
    "ITEM_COUNT",
)

# Convert to DynamicFrame using the same name
transformed = DynamicFrame.fromDF(aggregated_df, glueContext)

# Write to staged bucket
print(f"Writing data to: {target_path}")

transformed = DynamicFrame.fromDF(aggregated_df, glueContext)

# The connectionName in connection_options affects the output
glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="s3",
    connection_options={
        "path": target_path,
        "partitionKeys": [],
    },
    format="csv",
    format_options={
        "separator": ",",
        "quoteChar": '"',
        "withHeader": True,
        "compression": "none",
    },
    transformation_ctx=f"{sc.applicationId}",

)

print(f"Successfully wrote {transformed.count()} records to {target_path}")
job.commit()